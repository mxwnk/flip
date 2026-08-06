import AppKit
import ApplicationServices
import OSLog

private let log = Logger(subsystem: Bundle.identifier, category: "startup")

// Not named main.swift on purpose: that filename means top-level code, which is
// nonisolated and so cannot touch a main-actor delegate.
@main
@MainActor
final class FlipApp: NSObject, NSApplicationDelegate {
    private var status = Permissions.Status(accessibility: false, screenRecording: false)
    private var poll: Timer?

    private let frontmost = FrontmostApp()
    private let store = WindowStore()
    private let thumbnails = ThumbnailStore()
    private lazy var presenter = OverlayPresenter(
        store: store, frontmost: frontmost, thumbnails: thumbnails
    )
    private var router: KeyRouter?
    private var tap: EventTap?

    static func main() {
        let delegate = FlipApp()
        let application = NSApplication.shared

        // Agent app: no Dock icon, never takes focus. Matches LSUIElement in
        // Info.plist, and keeps runs straight out of .build behaving the same.
        application.setActivationPolicy(.accessory)
        application.delegate = delegate
        application.run()
    }

    func applicationDidFinishLaunching(_: Notification) {
        log.notice("Flip \(Bundle.main.shortVersion, privacy: .public) starting")
        checkAXShimLinkage()

        status = Permissions.request()
        Permissions.report(status)

        frontmost.startObserving()
        startWindowStoreIfPermitted()
        startInputIfPermitted()

        // Grants are made while the app is already running, and the switch is not
        // announced anywhere, so the only way to notice is to look again.
        poll = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.reportIfChanged() }
        }
    }

    private func reportIfChanged() {
        let latest = Permissions.current()
        guard latest != status else { return }

        status = latest
        Permissions.report(latest)

        // Accessibility is usually granted after the first launch, and neither the
        // tap nor the observers could have been created before that.
        startWindowStoreIfPermitted()
        startInputIfPermitted()
    }

    private var storeIsRunning = false

    private func startWindowStoreIfPermitted() {
        guard !storeIsRunning, status.accessibility else { return }

        storeIsRunning = true
        store.onWindowDefocused = { [weak self] id in self?.thumbnails.warm([id]) }
        store.start()

        // Nothing has lost focus yet, so the first Alt-Tab would otherwise be the
        // only one that opens onto empty tiles.
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

        KeyboardLayout.observeInputSourceChanges { [weak router] in
            router?.rebuildBindings()
        }

        let tap = EventTap(observing: [.keyDown, .flagsChanged]) { type, event in
            router.handle(type: type, event: event)
        }
        self.tap = tap
        tap.start()
    }

    /// A private symbol that resolves at build time can still be missing at run
    /// time. Calling it once against the system-wide element settles the question
    /// on every launch: that element is not a window, so the call is expected to
    /// fail — the point is that it returns at all instead of trapping.
    private func checkAXShimLinkage() {
        _ = AXBridge.windowID(of: AXUIElementCreateSystemWide())
        log.notice("_AXUIElementGetWindow resolved")
    }
}
