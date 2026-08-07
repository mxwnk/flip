import AppKit
import OSLog
import SwiftUI

/// The overlay. Panels are built once at launch and never torn down: showing one
/// is an `orderFront`, hiding it an `orderOut`. There is one per screen, because
/// the placement setting can ask for the grid on every display at once.
@MainActor
final class OverlayPresenter: SwitcherPresenting {
    private let log = Logger(subsystem: Bundle.identifier, category: "switcher")
    private let store: WindowStore
    private let frontmost: FrontmostApp
    private let thumbnails: ThumbnailStore
    private let settings: SettingsStore

    private let model = OverlayModel()
    /// One per screen, all drawing the same model. Only the first `inUse` of them
    /// are positioned and shown for a given session.
    private var panels: [NSPanel] = []
    private var inUse = 0
    /// A session is running. The panel may not be on screen yet: a tap released
    /// inside the delay commits without ever showing anything.
    private var isVisible = false
    private var currentSource: Source?
    private var lifetime: Timer?
    private var reveal: Timer?
    /// Where the pointer was when the keyboard last had its say. Hovering is
    /// ignored until it has moved away from here — see `hover`.
    private var pointerAnchor: CGPoint?

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

        // Every screen gets its own now rather than on the first keypress: the
        // panel and its SwiftUI machinery are the expensive part, and not paying
        // for them at ⌥Tab is what the whole design is arranged around.
        ensurePanels(max(NSScreen.screens.count, 1))
    }

    private func ensurePanels(_ count: Int) {
        while panels.count < count { panels.append(makePanel(index: panels.count)) }
    }

    private func makePanel(index: Int) -> NSPanel {
        let panel = NSPanel(
            contentRect: NSScreen.main?.frame ?? .zero,
            // Non-activating: the switcher must not become the application it is
            // about to switch away from.
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

        // isFloatingPanel rewrites the level, so it must come first. Reversed, the
        // overlay sits at level 3 — under the menu bar and full-screen windows.
        panel.isFloatingPanel = true
        panel.level = .screenSaver
        // The panel covers the whole screen, so accepting mouse events means it
        // also swallows clicks on the dimmed backdrop. Those cancel; see `click`.
        panel.ignoresMouseEvents = false
        panel.acceptsMouseMovedEvents = true

        let host = OverlayHostingView(rootView: OverlayView(model: model))
        panel.contentView = host

        // Build SwiftUI's machinery now, not on the first Alt-Tab.
        host.layoutSubtreeIfNeeded()

        // The index is captured so a point can be resolved against the panel it
        // came from; with the grid on three screens they are three coordinate
        // spaces holding the same picture.
        host.onPointerMoved = { [weak self] point in self?.hover(at: point, on: index) }
        host.onClick = { [weak self] point in self?.click(at: point, on: index) }

        return panel
    }

    /// Where the grid belongs, per the setting.
    private func targetScreens() -> [NSScreen] {
        switch settings.settings.overlayPlacement {
        case .activeWindow:
            return [ActiveScreen.current()]
        case .primaryDisplay:
            return [ScreenGeometry.primary ?? ActiveScreen.current()]
        case .everyDisplay:
            return NSScreen.screens.isEmpty ? [ActiveScreen.current()] : NSScreen.screens
        }
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

    func reachApplication(_ bundleID: String) {
        let windows = store.windows(
            ofBundleID: bundleID, includingMinimized: true, fromEverySpace: everySpace
        )

        // NSRunningApplication.activate() brings the application forward but leaves
        // its windows in the Dock, so one with nothing but minimised windows would
        // arrive showing nothing at all.
        guard let target = windows.first, windows.allSatisfy(\.isMinimized) else {
            return AppLauncher.activate(bundleID)
        }

        store.focus(target)
    }

    func arrangeWindow(_ arrangement: WindowArrangement) {
        store.arrange(arrangement)
    }

    func move(by step: Int) {
        guard isVisible, !model.windows.isEmpty else { return }

        let count = model.windows.count
        model.selected = (model.selected + step % count + count) % count
        anchorPointer()
    }

    func moveRow(by step: Int) {
        guard isVisible, !model.windows.isEmpty else { return }

        model.selected = model.layout.index(
            movingRowBy: step,
            from: model.selected,
            count: model.windows.count
        )
        anchorPointer()
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

    // MARK: - Mouse

    /// Hovering does not take over until the pointer has actually moved. A grid
    /// opening under a resting pointer must not discard the selection the keyboard
    /// just made, and the same applies after every arrow key.
    private func hover(at point: CGPoint, on panelIndex: Int) {
        guard isVisible, panelIndex < inUse, panels[panelIndex].isVisible else { return }

        if let anchor = pointerAnchor {
            let mouse = NSEvent.mouseLocation
            guard hypot(mouse.x - anchor.x, mouse.y - anchor.y) > 2 else { return }

            pointerAnchor = nil
        }

        guard let tile = tile(at: point, on: panelIndex), tile != model.selected else { return }

        model.selected = tile
    }

    private func click(at point: CGPoint, on panelIndex: Int) {
        guard isVisible, panelIndex < inUse, panels[panelIndex].isVisible else { return }

        // The router decides synchronously and has no idea a click happened, so it
        // would keep swallowing keys until the leader is let go. Both paths end the
        // session, so both have to tell it.
        defer { onUnexpectedClose?() }

        // Outside the grid is the dimmed backdrop rather than a tile: give up,
        // instead of committing whatever happened to be selected.
        guard let tile = tile(at: point, on: panelIndex) else { return cancel() }

        model.selected = tile
        commit()
    }

    /// The grid is centred in whichever panel the point came from, so the panel's
    /// own size is the container the hit test needs.
    private func tile(at point: CGPoint, on panelIndex: Int) -> Int? {
        model.layout.index(
            at: point, in: panels[panelIndex].frame.size, count: model.windows.count
        )
    }

    /// Kept in screen coordinates, so it holds however many displays the grid is
    /// drawn on and whichever one the pointer happens to be over.
    private func anchorPointer() {
        pointerAnchor = NSEvent.mouseLocation
    }

    // MARK: - Internals

    /// Which question the overlay answers. Changing it narrows an open overlay
    /// instead of stepping it along.
    private enum Source: Equatable {
        case allWindows
        case application(String)
    }

    private func windows(for source: Source) -> [WindowInfo] {
        switch source {
        case .allWindows:
            // Exclusions apply here only: naming an application by key is explicit.
            let excluded = Set(settings.settings.excludedBundleIDs)
            return store.windows(includingMinimized: true, fromEverySpace: everySpace)
                .filter { window in window.bundleID.map { !excluded.contains($0) } ?? true }
        case .application(let bundleID):
            return store.windows(
                ofBundleID: bundleID, includingMinimized: true, fromEverySpace: everySpace
            )
        }
    }

    private var everySpace: Bool { settings.settings.showWindowsFromEverySpace }

    private func open(_ source: Source, step: Int) {
        // Same question: walk the list rather than rebuild it under the selection.
        if isVisible, currentSource == source {
            move(by: step)
            return
        }

        let started = DispatchTime.now().uptimeNanoseconds
        let windows = windows(for: source)

        guard !windows.isEmpty else {
            log.debug("nothing to show for \(String(describing: source), privacy: .public)")

            // Narrowing to nothing leaves the overlay standing. Only a failed open
            // is reported, or the router keeps swallowing keys.
            if !isVisible { onUnexpectedClose?() }
            return
        }

        let wasVisible = isVisible
        present(windows, from: source)

        // Opening steps onto the previous window; narrowing does not, since the
        // application was named and its own top window is the answer.
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
        let screens = targetScreens()
        ensurePanels(screens.count)

        // Laid out for the narrowest of them, so one grid fits every screen it is
        // drawn on rather than spilling off the small one.
        let narrowest = screens.min { $0.frame.width < $1.frame.width } ?? screens[0]

        model.windows = windows
        model.selected = 0
        model.layout = OverlayLayout(count: windows.count, screen: narrowest.frame.size)
        model.thumbnails = alreadyCaptured(windows)

        for (index, screen) in screens.enumerated() {
            panels[index].setFrame(screen.frame, display: false)
        }
        inUse = screens.count

        let wasRunning = isVisible
        isVisible = true
        currentSource = source
        anchorPointer()

        // Narrowing keeps whatever the session already decided, so holding the
        // leader and pressing a key does not restart the wait.
        if !wasRunning { scheduleReveal() }
        if panels.prefix(inUse).contains(where: \.isVisible) {
            requestMissingThumbnails(for: windows)
        }

        lifetime = Timer.scheduledTimer(withTimeInterval: Configuration.maxOverlayLifetime, repeats: false) { _ in
            MainActor.assumeIsolated { [weak self] in
                guard let self, isVisible else { return }

                log.error("overlay outlived its welcome; closing")
                hide()
                onUnexpectedClose?()
            }
        }
    }

    /// Waiting means the selection exists but nothing has been drawn. Releasing
    /// the leader from here is the fast path the delay is for.
    private func scheduleReveal() {
        let delay = settings.settings.overlayDelay.seconds
        guard delay > 0 else { return show() }

        reveal = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { _ in
            MainActor.assumeIsolated { [weak self] in
                guard let self, isVisible else { return }

                show()
            }
        }
    }

    private func show() {
        for panel in panels.prefix(inUse) { panel.orderFront(nil) }
        requestMissingThumbnails(for: model.windows)

        log.debug("overlay shown on \(self.inUse, privacy: .public) display(s)")
    }

    private func hide() {
        reveal?.invalidate()
        reveal = nil
        lifetime?.invalidate()
        lifetime = nil

        for panel in panels { panel.orderOut(nil) }
        inUse = 0
        isVisible = false
        currentSource = nil
        model.windows = []
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
        // Off means never captured, which is what makes Screen Recording optional.
        guard settings.settings.showThumbnails else { return }

        // Selected tile first.
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
