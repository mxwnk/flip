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
        store: store, frontmost: frontmost, thumbnails: thumbnails, config: config
    )
    private var router: KeyRouter?
    private var control: ControlServer?
    private var tap: EventTap?
    private var menuBar: MenuBarItem?

    /// Not persisted: coming back to a switcher that silently does nothing is
    /// worse than one that resumed.
    private var isPaused = false

    private let config = ConfigStore()
    private lazy var settingsWindow = SettingsWindow(config: config)
    private lazy var updates = UpdateChecker(config: config)
    private lazy var inputSources = InputSourceSwitcher(config: config)
    private lazy var diagnosticsWindow = DiagnosticsWindow { [weak self] in self?.diagnostics() }
    private lazy var aboutWindow = AboutWindow(
        onShowDiagnostics: { [weak self] in self?.diagnosticsWindow.show() }
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

        config.load()
        config.watchForExternalEdits()
        // A key being recorded must reach the settings window, not the binding
        // it is already on. Must not resume out of a deliberate pause.
        config.onKeyCapture = { [weak self] capturing in
            self?.keyCaptureChanged(capturing)
        }
        LoginItem.migrateFromLegacyAgent()

        menuBar = MenuBarItem(
            onShowSettings: { [weak self] in self?.settingsWindow.show() },
            onShowUpdate: { NSWorkspace.shared.open(UpdateChecker.releases) },
            onShowAbout: { [weak self] in self?.aboutWindow.show() },
            onShowDiagnostics: { [weak self] in self?.diagnosticsWindow.show() },
            onTogglePause: { [weak self] in self?.togglePause() },
            onApplyLayout: { [weak self] id in self?.applyLayout(id) },
            onExplainSecureInput: { [weak self] in self?.explainSecureInput() }
        )
        updateMenuBar()

        updates.onFound = { [weak self] in
            guard let self else { return }

            menuBar?.showUpdate(available: updates.available)
        }
        updates.start()

        frontmost.startObserving()
        inputSources.start()
        startWindowStoreIfPermitted()
        startInputIfPermitted()
        startControlServer()

        // Grants happen while running and are announced nowhere.
        poll = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.reportIfChanged()
                self?.reportSecureInputIfChanged()
                self?.retryInputIfNeeded()
            }
        }
    }

    private func updateMenuBar() {
        menuBar?.update(
            for: status,
            paused: isPaused,
            inputWorking: inputWorking,
            canReadWindowIDs: canReadWindowIDs,
            layouts: config.settings.arrange.layouts,
            layoutLeader: config.settings.arrange.leader.label
        )
    }

    private func reportIfChanged() {
        let latest = Permissions.current()
        guard latest != status else { return }

        status = latest
        Permissions.report(latest)
        updateMenuBar()

        // Accessibility usually arrives after the first launch.
        startWindowStoreIfPermitted()
        startInputIfPermitted()
    }

    /// Counted: two recorders can overlap, and the first one stopping must not
    /// switch the tap back on under the second.
    private var keyCaptures = 0

    private func keyCaptureChanged(_ capturing: Bool) {
        keyCaptures = max(0, keyCaptures + (capturing ? 1 : -1))
        tap?.setEnabled(keyCaptures == 0 && !isPaused)
    }

    private var secureInput = SecureInputEpisode()
    private lazy var secureInputNotice = SecureInputNotice()

    private func reportSecureInputIfChanged() {
        switch secureInput.observe(isOn: SecureInputHolder.isOn, at: Date()) {
        case .started: secureInputStarted()
        case .ended: secureInputEnded()
        case .needsExplaining: explainSecureInput()
        case .none: break
        }
    }

    private func secureInputStarted() {
        menuBar?.showSecureInput(isOn: true)

        let reported = SecureInputHolder.current()?.description ?? "nobody"
        log.error("secure input is on, macOS attributes it to \(reported, privacy: .public); no key reaches Flip")
    }

    private func secureInputEnded() {
        menuBar?.showSecureInput(isOn: false)
        secureInputNotice.showResolved()
        log.notice("secure input released; keys reach Flip again")
    }

    private func explainSecureInput() {
        secureInputNotice.show()
        log.notice("explaining secure input")
    }

    private func diagnostics() -> DiagnosticsReport {
        Diagnostics.report(
            status: status,
            isPaused: isPaused,
            settings: config.settings,
            bindingCount: config.bindings.count,
            canReadWindowIDs: canReadWindowIDs,
            secureInputHolder: SecureInputHolder.current(),
            windowCount: store.windows(
                includingMinimized: true,
                fromEverySpace: config.settings.switcher.showWindowsFromEverySpace
            ).count
        )
    }

    private func togglePause() {
        isPaused.toggle()
        tap?.setEnabled(!isPaused && keyCaptures == 0)

        // An overlay left on screen would have no keys to close it.
        if isPaused { presenter.cancel(); router?.overlayDidClose() }

        updateMenuBar()
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
        // Nothing has lost focus yet, so the first Alt-Tab would find empty tiles.
        store.start { [weak self] ids in
            guard let self else { return }

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

    /// Answers on the socket thread. Reading windows is safe there; anything
    /// that is not hops to main and reports acceptance, not completion.
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
            // Everything Flip knows, not the overlay's narrower set: `focus`
            // reaches any of them.
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
            guard let arrangement = WindowArrangement(rawValue: name)
            else { return .failure("unknown arrangement '\(name)'") }

            store.arrange(arrangement)
            return .ok

        case .layout(let name):
            guard let matched = layouts.layout(named: name) else {
                let available = layouts.all.map(\.name).joined(separator: ", ")
                let message = available.isEmpty
                    ? "no layouts configured in settings"
                    : "unknown layout '\(name)' — available: \(available)"
                return .failure(message)
            }

            store.applyLayout(matched)
            return .ok

        case .listLayouts:
            return .layouts(layouts.all.map(\.name))

        case .switcher:
            Task { @MainActor [weak self] in
                guard let self else { return }

                presenter.showAllWindows(step: 1)
                router?.overlayWasOpenedExternally()
            }
            return .ok

        case .permissions:
            // Answered from this thread on purpose: both are C calls with no
            // AppKit behind them, and the socket must never wait on the main
            // thread to hear back.
            let status = Permissions.current()

            return .permissions(ControlPermissions(
                accessibility: status.accessibility,
                screenRecording: status.screenRecording
            ))

        case .pause, .resume:
            let wanted = command.isPause
            Task { @MainActor [weak self] in
                guard let self, isPaused != wanted else { return }

                togglePause()
            }
            return .ok
        }
    }

    private let layouts = LayoutStore()

    private func applyLayout(_ id: UUID) {
        guard let layout = layouts.layout(id: id) else { return }

        store.applyLayout(layout)
    }

    private func buildRouter() {
        let router = KeyRouter(presenter: presenter, frontmost: frontmost)
        self.router = router

        router.onApplyLayout = { [weak self] id in self?.applyLayout(id) }

        presenter.onUnexpectedClose = { [weak router] in router?.overlayDidClose() }

        // Bindings resolve against the layout, so both invalidate them.
        let reapply = { [weak self, weak router] in
            guard let self, let router else { return }

            layouts.update(to: config.settings.arrange.layouts)
            router.apply(config.bindings, settings: config.settings)
            updateMenuBar()
        }
        reapply()
        config.onChange = reapply
        KeyboardLayout.observeInputSourceChanges(onChange: reapply)
    }

    /// The port is created on the tap's own thread, so failure lands after
    /// `start()` returned and `tap` is non-nil. Clearing it lets the poll retry.
    private func inputStateChanged(_ running: Bool) {
        if !running { tap = nil }
        guard running != inputWorking else { return }

        inputWorking = running
        updateMenuBar()
    }

    /// Usually a grant that has not propagated yet. Every fifth poll, so a
    /// permanent failure does not start a thread every two seconds.
    private func retryInputIfNeeded() {
        guard tap == nil, status.accessibility else { return }
        guard retryCountdown <= 0 else {
            retryCountdown -= 1
            return
        }

        retryCountdown = 5
        startInputIfPermitted()
    }

    /// Two copies mean two event taps racing, the loser silently swallowing
    /// keys. Only the oldest stays; a symmetric check would make all of them
    /// leave.
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

    /// Weakly imported, so an absent symbol starts instead of dying — but a
    /// window with no id cannot be matched, so nothing works.
    private func checkAXShimLinkage() {
        canReadWindowIDs = FlipCanReadWindowIDs()
        guard canReadWindowIDs else {
            log.error("_AXUIElementGetWindow is missing here; windows cannot be identified")
            return
        }

        log.notice("_AXUIElementGetWindow resolved")
    }
}

/// Thread-safe snapshot of configured window layouts, accessed from the socket thread
/// and the event tap without holding up the main actor.
private final class LayoutStore: @unchecked Sendable {
    private let lock = NSLock()
    private var snapshot: [WindowLayout] = []

    func update(to layouts: [WindowLayout]) {
        lock.lock()
        snapshot = layouts
        lock.unlock()
    }

    var all: [WindowLayout] {
        lock.lock()
        defer { lock.unlock() }
        return snapshot
    }

    func layout(id: UUID) -> WindowLayout? {
        lock.lock()
        defer { lock.unlock() }
        return snapshot.first { $0.id == id }
    }

    func layout(named name: String) -> WindowLayout? {
        lock.lock()
        defer { lock.unlock() }
        return snapshot.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }
}
