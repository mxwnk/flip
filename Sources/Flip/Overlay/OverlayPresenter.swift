import AppKit
import OSLog
import SwiftUI

/// The overlay, and the thing the key router drives.
///
/// The panel is built once at launch and never torn down — showing it is an
/// `orderFront`, hiding it an `orderOut`. That is the difference the measurements
/// pointed at: the Hammerspoon version created a fresh canvas and a fresh window
/// on every single Alt-Tab, which cost about 12 ms before anything was drawn.
@MainActor
final class OverlayPresenter: SwitcherPresenting {
    private let log = Logger(subsystem: Bundle.identifier, category: "switcher")
    private let store: WindowStore
    private let frontmost: FrontmostApp
    private let thumbnails: ThumbnailStore
    private let settings: SettingsStore

    private let model = OverlayModel()
    private let panel: NSPanel
    private var isVisible = false
    private var currentSource: Source?
    private var lifetime: Timer?

    var onUnexpectedClose: (() -> Void)?

    init(
        store: WindowStore,
        frontmost: FrontmostApp,
        thumbnails: ThumbnailStore,
        settings: SettingsStore
    ) {
        self.store = store
        self.frontmost = frontmost
        self.thumbnails = thumbnails
        self.settings = settings

        panel = NSPanel(
            contentRect: NSScreen.main?.frame ?? .zero,
            // Non-activating is what keeps the overlay from stealing focus, which
            // matters more than it sounds: the switcher must not itself become the
            // application it is about to switch away from.
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.collectionBehavior = [
            .canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle,
        ]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false

        // Order matters here, and getting it wrong is invisible: the isFloatingPanel
        // setter rewrites the window level to .floating, so setting the level first
        // silently left the overlay at level 3 — above ordinary windows, but under
        // the menu bar and under anything running full screen.
        panel.isFloatingPanel = true
        panel.level = .screenSaver
        // Keyboard only for now; the router owns every interaction.
        panel.ignoresMouseEvents = true

        let host = NSHostingView(rootView: OverlayView(model: model))
        panel.contentView = host

        // Force SwiftUI to build its machinery now rather than on the first
        // Alt-Tab, where it would be the one visible cost left.
        host.layoutSubtreeIfNeeded()
    }

    // MARK: - SwitcherPresenting

    func showAllWindows(step: Int) {
        open(.allWindows, step: step)
    }

    func showWindows(of bundleID: String, step: Int) {
        open(.application(bundleID), step: step)
    }

    func showFrontmostAppWindows(step: Int) {
        guard let bundleID = frontmost.bundleID else { return }

        open(.application(bundleID), step: step)
    }

    func move(by step: Int) {
        guard isVisible, !model.windows.isEmpty else { return }

        let count = model.windows.count
        model.selected = (model.selected + step % count + count) % count
    }

    func moveRow(by step: Int) {
        guard isVisible, !model.windows.isEmpty else { return }

        model.selected = model.layout.index(
            movingRowBy: step,
            from: model.selected,
            count: model.windows.count
        )
    }

    func commit() {
        guard isVisible else { return }

        let window = model.windows.indices.contains(model.selected)
            ? model.windows[model.selected]
            : nil
        hide()

        guard let window else { return }

        log.debug("focusing \(window.applicationName, privacy: .public) — \(window.title, privacy: .public)")
        store.focus(window)
    }

    func cancel() {
        guard isVisible else { return }

        hide()
    }

    // MARK: - Internals

    /// Which question the overlay is currently answering. Holding Alt and pressing
    /// an application key changes it without closing anything, which is what makes
    /// Alt-S narrow an open overlay to Spotify instead of stepping it along by one.
    private enum Source: Equatable {
        case allWindows
        case application(String)
    }

    private func windows(for source: Source) -> [WindowInfo] {
        switch source {
        case .allWindows:
            // Exclusions apply here and nowhere else. Naming an application by key
            // is an explicit request for it, and refusing that would be surprising.
            let excluded = Set(settings.settings.excludedBundleIDs)
            return store.currentSpaceWindows().filter { window in
                window.bundleID.map { !excluded.contains($0) } ?? true
            }
        case .application(let bundleID):
            return store.currentSpaceWindows(ofBundleID: bundleID, includingMinimized: true)
        }
    }

    private func open(_ source: Source, step: Int) {
        // Same question as before, so this is another tap of the same key: walk the
        // list rather than rebuilding it underneath the selection.
        if isVisible, currentSource == source {
            move(by: step)
            return
        }

        let started = DispatchTime.now().uptimeNanoseconds
        let windows = windows(for: source)

        guard !windows.isEmpty else {
            log.debug("nothing to show for \(String(describing: source), privacy: .public)")

            // Narrowing to an application with nothing on this space leaves the
            // overlay standing rather than closing it out from under the user. Only
            // a failed *open* has to be reported, or the router keeps believing an
            // overlay is up and swallows keys that should pass through.
            if !isVisible { onUnexpectedClose?() }
            return
        }

        let wasVisible = isVisible
        present(windows, from: source)

        // Opening steps onto the previous window, which is the whole point of a
        // switcher. Narrowing does not: the application was named, so its own most
        // recent window is the answer, and stepping would skip past it.
        if !wasVisible { move(by: step) }

        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000
        log.notice("""
        \(wasVisible ? "narrowed" : "opened", privacy: .public) to \
        \(windows.count, privacy: .public) windows \
        in \(String(format: "%.2f", elapsed), privacy: .public)ms, \
        \(self.model.thumbnails.count, privacy: .public) thumbnails ready
        """)
    }

    private func present(_ windows: [WindowInfo], from source: Source) {
        let screen = ActiveScreen.current()

        model.windows = windows
        model.selected = 0
        model.layout = OverlayLayout(count: windows.count, screen: screen.frame.size)
        model.thumbnails = alreadyCaptured(windows)

        panel.setFrame(screen.frame, display: false)
        panel.orderFront(nil)
        isVisible = true
        currentSource = source

        log.debug("""
        panel \(NSStringFromRect(self.panel.frame), privacy: .public) \
        visible=\(self.panel.isVisible, privacy: .public) \
        onActiveSpace=\(self.panel.isOnActiveSpace, privacy: .public) \
        alpha=\(self.panel.alphaValue, privacy: .public) \
        screen=\(NSStringFromRect(screen.frame), privacy: .public)
        """)

        requestMissingThumbnails(for: windows)

        lifetime = Timer.scheduledTimer(withTimeInterval: Configuration.maxOverlayLifetime, repeats: false) { _ in
            MainActor.assumeIsolated { [weak self] in
                guard let self, isVisible else { return }

                log.error("overlay outlived its welcome; closing")
                hide()
                onUnexpectedClose?()
            }
        }
    }

    private func hide() {
        lifetime?.invalidate()
        lifetime = nil

        panel.orderOut(nil)
        isVisible = false
        currentSource = nil
        model.windows = []
        // The images themselves stay in the store; this only drops the references
        // the closed overlay was holding.
        model.thumbnails = [:]
    }

    // MARK: - Thumbnails

    private func alreadyCaptured(_ windows: [WindowInfo]) -> [CGWindowID: CGImage] {
        guard settings.settings.showThumbnails else { return [:] }

        var known: [CGWindowID: CGImage] = [:]
        for window in windows where !window.isMinimized {
            known[window.id] = thumbnails.cached(window.id)
        }

        return known.compactMapValues { $0 }
    }

    private func requestMissingThumbnails(for windows: [WindowInfo]) {
        // Turned off means never captured, not captured and hidden: that is what
        // makes the Screen Recording grant genuinely optional.
        guard settings.settings.showThumbnails else { return }

        // Selected tile first: it is the one being looked at, so its capture goes
        // in ahead of the rest.
        let selected = model.selected
        let ordered = ([windows[selected]] + windows.enumerated().filter { $0.offset != selected }.map(\.element))
            .filter { !$0.isMinimized }
            .map(\.id)

        thumbnails.fill(ordered) { [weak self] id, image in
            guard let self, isVisible, model.windows.contains(where: { $0.id == id })
            else { return }

            model.thumbnails[id] = image
        }
    }
}
