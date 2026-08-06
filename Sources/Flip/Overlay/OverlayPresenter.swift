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

    private let model = OverlayModel()
    private let panel: NSPanel
    private var isVisible = false
    private var lifetime: Timer?

    /// Last resort against a modifier state that never reports itself as released,
    /// which would otherwise leave the overlay on screen for good.
    private static let maxLifetime: TimeInterval = 30

    var onUnexpectedClose: (() -> Void)?

    init(store: WindowStore, frontmost: FrontmostApp) {
        self.store = store
        self.frontmost = frontmost

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
        open(step: step) { [self] in store.currentSpaceWindows() }
    }

    func showWindows(of bundleID: String, step: Int) {
        open(step: step) { [self] in
            store.currentSpaceWindows(ofBundleID: bundleID, includingMinimized: true)
        }
    }

    func showFrontmostAppWindows(step: Int) {
        guard let bundleID = frontmost.bundleID else { return }

        showWindows(of: bundleID, step: step)
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

    /// Reopening replaces the list; stepping again keeps it, so the selection can
    /// walk a list that does not shift underneath it.
    private func open(step: Int, source: () -> [WindowInfo]) {
        if !isVisible {
            let started = DispatchTime.now().uptimeNanoseconds
            let windows = source()

            // Nothing to switch between. The router still believes the overlay is
            // up, so it has to be told otherwise or it will swallow the next keys.
            guard !windows.isEmpty else {
                onUnexpectedClose?()
                return
            }

            present(windows)

            let elapsed = Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000
            log.notice("""
            opened with \(windows.count, privacy: .public) windows \
            in \(String(format: "%.2f", elapsed), privacy: .public)ms
            """)
        }

        move(by: step)
    }

    private func present(_ windows: [WindowInfo]) {
        let screen = NSScreen.main ?? NSScreen.screens[0]

        model.windows = windows
        model.selected = 0
        model.layout = OverlayLayout(count: windows.count, screen: screen.frame.size)

        panel.setFrame(screen.frame, display: false)
        panel.orderFront(nil)
        isVisible = true

        log.debug("""
        panel \(NSStringFromRect(self.panel.frame), privacy: .public) \
        visible=\(self.panel.isVisible, privacy: .public) \
        onActiveSpace=\(self.panel.isOnActiveSpace, privacy: .public) \
        alpha=\(self.panel.alphaValue, privacy: .public) \
        screen=\(NSStringFromRect(screen.frame), privacy: .public)
        """)

        lifetime = Timer.scheduledTimer(withTimeInterval: Self.maxLifetime, repeats: false) { _ in
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
        model.windows = []
    }
}
