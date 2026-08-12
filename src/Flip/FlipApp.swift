import AppKit
import ApplicationServices
import CAXShim
import FlipControl
import OSLog

private let log = Logger(subsystem: Bundle.identifier, category: "startup")

// Not main.swift: that filename means top-level code, which is nonisolated and
// cannot touch a main-actor delegate.
@main
@MainActor
final class FlipApp: NSObject, NSApplicationDelegate {
    private var status = Permissions.Status(accessibility: false, screenRecording: false)
    private var poll: Timer?

    private let frontmost = FrontmostApp()
    private let store = WindowStore()
    private let thumbnails = ThumbnailStore()
    private lazy var presenter = OverlayPresenter(
        store: store, frontmost: frontmost, thumbnails: thumbnails, settings: settings
    )
    private var router: KeyRouter?
    private var control: ControlServer?
    private var tap: EventTap?
    private var menuBar: MenuBarItem?

    /// Not persisted: pausing lasts a screen share or a game, and returning to a
    /// switcher that silently does nothing is worse than one that resumed.
    private var isPaused = false

    private let bindings = BindingStore()
    private let settings = SettingsStore()
    private lazy var settingsWindow = SettingsWindow(settings: settings, bindings: bindings)
    private lazy var updates = UpdateChecker(settings: settings)
    private lazy var aboutWindow = AboutWindow(
        onCopyDiagnostics: { [weak self] in self?.diagnostics() ?? "" }
    )

    static func main() {
        let delegate = FlipApp()
        let application = NSApplication.shared

        // Agent app: no Dock icon, never takes focus. Matches LSUIElement.
        application.setActivationPolicy(.accessory)
        application.delegate = delegate
        application.run()
    }

    func applicationDidFinishLaunching(_: Notification) {
        guard isOnlyInstance() else { return }

        log.notice("Flip \(Bundle.main.shortVersion, privacy: .public) starting")
        checkAXShimLinkage()

        status = Permissions.request()
        Permissions.report(status)

        bindings.load()
        bindings.watchForExternalEdits()
        // A key being recorded has to reach the settings window rather than the
        // binding it is already on. Pausing respects itself: resuming from here
        // must not undo it.
        bindings.onKeyCapture = { [weak self] capturing in
            guard let self else { return }

            tap?.setEnabled(!capturing && !isPaused)
        }
        settings.load()
        LoginItem.migrateFromLegacyAgent()

        menuBar = MenuBarItem(
            onShowSettings: { [weak self] in self?.settingsWindow.show() },
            onShowUpdate: { NSWorkspace.shared.open(UpdateChecker.releases) },
            onShowAbout: { [weak self] in self?.aboutWindow.show() },
            onCopyDiagnostics: { [weak self] in
                guard let self else { return }

                Diagnostics.copyToPasteboard(diagnostics())
                log.notice("diagnostics copied to the clipboard")
            },
            onTogglePause: { [weak self] in self?.togglePause() }
        )
        menuBar?.update(for: status, paused: isPaused, inputWorking: inputWorking, canReadWindowIDs: canReadWindowIDs)

        updates.onFound = { [weak self] in
            guard let self else { return }

            menuBar?.showUpdate(available: updates.available)
        }
        updates.start()

        frontmost.startObserving()
        startWindowStoreIfPermitted()
        startInputIfPermitted()
        startControlServer()

        // Grants happen while running and are announced nowhere.
        poll = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.reportIfChanged()
                self?.retryInputIfNeeded()
            }
        }
    }

    private func reportIfChanged() {
        let latest = Permissions.current()
        guard latest != status else { return }

        status = latest
        Permissions.report(latest)
        menuBar?.update(for: latest, paused: isPaused, inputWorking: inputWorking, canReadWindowIDs: canReadWindowIDs)

        // Accessibility usually arrives after the first launch.
        startWindowStoreIfPermitted()
        startInputIfPermitted()
    }

    private func diagnostics() -> String {
        Diagnostics.report(
            status: status,
            isPaused: isPaused,
            settings: settings.settings,
            bindingCount: bindings.bindings.count,
            canReadWindowIDs: canReadWindowIDs,
            windowCount: store.windows(
                includingMinimized: true,
                fromEverySpace: settings.settings.showWindowsFromEverySpace
            ).count
        )
    }

    private func togglePause() {
        isPaused.toggle()
        tap?.setEnabled(!isPaused)

        // An overlay left on screen would have no keys to close it.
        if isPaused { presenter.cancel(); router?.overlayDidClose() }

        menuBar?.update(for: status, paused: isPaused, inputWorking: inputWorking, canReadWindowIDs: canReadWindowIDs)
        log.notice("\(self.isPaused ? "paused" : "resumed", privacy: .public)")
    }

    private var storeIsRunning = false
    /// False once the tap has failed to come up, which the menu bar shows.
    private var inputWorking = true
    /// False where `_AXUIElementGetWindow` is absent. Shown, not silent.
    private var canReadWindowIDs = true
    private var retryCountdown = 0

    private func startWindowStoreIfPermitted() {
        guard !storeIsRunning, status.accessibility else { return }

        storeIsRunning = true
        store.onWindowDefocused = { [weak self] id in self?.thumbnails.warm([id]) }
        thumbnails.expectedSize = { [weak store] id in store?.size(of: id) }
        store.start()

        // Nothing has lost focus yet, so the first Alt-Tab would find empty tiles.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self else { return }

            let ids = store.allWindowIDs()
            log.notice("warming \(ids.count, privacy: .public) thumbnails at startup")
            thumbnails.warm(ids)
        }
    }

    private func startInputIfPermitted() {
        guard tap == nil, status.accessibility else { return }

        // Built once. A retry must not run this again, or every attempt stacks
        // another set of onChange observers on the same stores.
        if router == nil { buildRouter() }
        guard let router else { return }

        let tap = EventTap(
            observing: [.keyDown, .flagsChanged],
            onState: { [weak self] running in
                Task { @MainActor in self?.inputStateChanged(running) }
            }
        ) { type, event in
            router.handle(type: type, event: event)
        }
        self.tap = tap
        tap.start()
    }

    /// The socket answers on its own thread. Reading windows is safe there —
    /// the store publishes under a lock — and everything that is not hops to
    /// main and reports that it was accepted rather than waiting for it.
    private func startControlServer() {
        control = ControlServer { [weak self] command in
            guard let self else { return .failure("Flip is shutting down") }

            return answer(command)
        }
        control?.start()
    }

    private nonisolated func answer(_ command: ControlCommand) -> ControlResponse {
        switch command {
        case .list:
            // Everything Flip knows, not the narrower set the overlay is
            // configured to show: a script asking what exists wants the whole
            // answer, and `focus` reaches any of them.
            let windows = store.windows(includingMinimized: true, fromEverySpace: true)

            return .windows(windows.map {
                ControlWindow(id: $0.id, app: $0.applicationName, title: $0.title, minimized: $0.isMinimized)
            })

        case .focus(let id):
            guard let window = store
                .windows(includingMinimized: true, fromEverySpace: true)
                .first(where: { $0.id == id })
            else { return .failure("no window with id \(id) — see `flip list`") }

            store.focus(window)
            return .ok

        case .arrange(let name):
            guard let arrangement = WindowArrangement(controlName: name)
            else { return .failure("unknown arrangement '\(name)'") }

            store.arrange(arrangement)
            return .ok

        case .switcher:
            Task { @MainActor [weak self] in
                guard let self else { return }

                presenter.showAllWindows(step: 1)
                router?.overlayWasOpenedExternally()
            }
            return .ok

        case .pause, .resume:
            let wanted = command.isPause
            Task { @MainActor [weak self] in
                guard let self, isPaused != wanted else { return }

                togglePause()
            }
            return .ok
        }
    }

    private func buildRouter() {
        let router = KeyRouter(presenter: presenter, frontmost: frontmost)
        self.router = router

        presenter.onUnexpectedClose = { [weak router] in router?.overlayDidClose() }

        // Bindings resolve against the layout, so both invalidate them.
        let reapply = { [weak self, weak router] in
            guard let self, let router else { return }

            router.apply(bindings.bindings, settings: settings.settings)
        }
        reapply()
        bindings.onChange = reapply
        settings.onChange = reapply
        KeyboardLayout.observeInputSourceChanges(onChange: reapply)
    }

    /// The port is created on the tap's own thread, so a failure lands after
    /// `start()` has already returned and `tap` is non-nil. Clearing it is what
    /// lets the poll try again — without this, one failed create meant no
    /// hotkeys until the next launch, and nothing said so.
    private func inputStateChanged(_ running: Bool) {
        if !running { tap = nil }
        guard running != inputWorking else { return }

        inputWorking = running
        menuBar?.update(for: status, paused: isPaused, inputWorking: running, canReadWindowIDs: canReadWindowIDs)
    }

    /// The usual cause is a grant that has not propagated yet, which clears on
    /// its own. Every fifth poll, so a permanent failure does not start a thread
    /// every two seconds.
    private func retryInputIfNeeded() {
        guard tap == nil, status.accessibility else { return }
        guard retryCountdown <= 0 else {
            retryCountdown -= 1
            return
        }

        retryCountdown = 5
        startInputIfPermitted()
    }

    /// Two copies mean two event taps racing, the loser silently swallowing keys.
    /// Only the oldest stays: a symmetric "is anyone else running" check makes
    /// every copy leave — three raced once and none survived. Exits zero, so
    /// KeepAlive treats it as deliberate.
    private func isOnlyInstance() -> Bool {
        let ourPID = ProcessInfo.processInfo.processIdentifier
        let ourLaunch = NSRunningApplication.current.launchDate ?? .distantPast

        let older = NSRunningApplication
            .runningApplications(withBundleIdentifier: Bundle.identifier)
            .filter { other in
                guard other.processIdentifier != ourPID else { return false }

                let theirLaunch = other.launchDate ?? .distantPast
                // A tie has to break the same way on both sides.
                if theirLaunch == ourLaunch { return other.processIdentifier < ourPID }

                return theirLaunch < ourLaunch
            }

        guard older.isEmpty else {
            log.notice("an older copy of Flip is running; stepping aside")
            NSApp.terminate(nil)
            return false
        }

        return true
    }

    /// Weakly imported, so a system without it starts instead of dying. Nothing
    /// works without it, though: a window with no id cannot be matched.
    private func checkAXShimLinkage() {
        canReadWindowIDs = FlipCanReadWindowIDs()
        guard canReadWindowIDs else {
            log.error("_AXUIElementGetWindow is missing here; windows cannot be identified")
            return
        }

        log.notice("_AXUIElementGetWindow resolved")
    }
}
