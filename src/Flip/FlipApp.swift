import AppKit
import ApplicationServices
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
    private var tap: EventTap?
    private var menuBar: MenuBarItem?

    /// Deliberately not persisted. Pausing is for the length of a screen share or
    /// a game, and coming back to a switcher that silently does nothing would be
    /// worse than one that resumed on its own.
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
        menuBar?.update(for: status, paused: isPaused)

        updates.onFound = { [weak self] in
            guard let self else { return }

            menuBar?.showUpdate(available: updates.available)
        }
        updates.start()

        frontmost.startObserving()
        startWindowStoreIfPermitted()
        startInputIfPermitted()

        // Grants happen while running and are announced nowhere.
        poll = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.reportIfChanged() }
        }
    }

    private func reportIfChanged() {
        let latest = Permissions.current()
        guard latest != status else { return }

        status = latest
        Permissions.report(latest)
        menuBar?.update(for: latest, paused: isPaused)

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

        menuBar?.update(for: status, paused: isPaused)
        log.notice("\(self.isPaused ? "paused" : "resumed", privacy: .public)")
    }

    private var storeIsRunning = false

    private func startWindowStoreIfPermitted() {
        guard !storeIsRunning, status.accessibility else { return }

        storeIsRunning = true
        store.onWindowDefocused = { [weak self] id in self?.thumbnails.warm([id]) }
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

        let tap = EventTap(observing: [.keyDown, .flagsChanged]) { type, event in
            router.handle(type: type, event: event)
        }
        self.tap = tap
        tap.start()
    }

    /// Two copies of Flip mean two event taps racing for every keystroke, and the
    /// loser silently swallowing keys. Registering the login item starts the agent
    /// immediately, so a second copy is now one click away rather than hypothetical.
    ///
    /// Only the oldest copy stays. A symmetric "is anyone else running" check
    /// makes every copy leave; three raced once and none survived. Exits zero, so
    /// the agent's KeepAlive treats it as deliberate.
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

    /// A private symbol resolving at build time can still be missing at run time.
    /// The call is expected to fail; the point is that it returns rather than traps.
    private func checkAXShimLinkage() {
        _ = AXBridge.windowID(of: AXUIElementCreateSystemWide())
        log.notice("_AXUIElementGetWindow resolved")
    }
}
