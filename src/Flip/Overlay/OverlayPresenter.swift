import AppKit
import OSLog
import SwiftUI

/// The overlay. Panels are built once at launch and never torn down: showing one
/// is an `orderFront`, hiding it an `orderOut`. One per screen, because the
/// placement setting can ask for the grid on every display at once.
@MainActor
final class OverlayPresenter: SwitcherPresenting {
    private let log = Logger(subsystem: Bundle.identifier, category: "switcher")
    private let store: WindowStore
    private let frontmost: FrontmostApp
    private let thumbnails: ThumbnailStore
    private let settings: SettingsStore

    private let model = OverlayModel()
    /// All drawing the same model; only the first `inUse` are shown.
    private var panels: [NSPanel] = []
    private var inUse = 0
    /// A session is running — the panel may not be drawn yet, since a tap
    /// released inside the delay commits without showing anything.
    private var isVisible = false
    private var currentSource: Source?
    private var lifetime: Timer?
    private var reveal: Timer?
    /// Where the pointer was when the keyboard last had its say; hovering is
    /// ignored until it moves away. See `hover`.
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

        // Now rather than on the first keypress: the panel and its SwiftUI
        // machinery are the expensive part, and not paying for them at ⌥Tab is
        // what the design is arranged around.
        ensurePanels(max(NSScreen.screens.count, 1))
    }

    private func ensurePanels(_ count: Int) {
        while panels.count < count { panels.append(makePanel(index: panels.count)) }
    }

    private func makePanel(index: Int) -> NSPanel {
        let panel = NSPanel(
            contentRect: NSScreen.main?.frame ?? .zero,
            // Non-activating: the switcher must not become the application it
            // is about to switch away from.
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

        // isFloatingPanel rewrites the level, so it comes first. Reversed, the
        // overlay sits at level 3 — under the menu bar and full-screen windows.
        panel.isFloatingPanel = true
        panel.level = .screenSaver
        // The panel covers the screen, so it also swallows clicks on the dimmed
        // backdrop. Those cancel; see `click`.
        panel.ignoresMouseEvents = false
        panel.acceptsMouseMovedEvents = true

        let host = OverlayHostingView(rootView: OverlayView(model: model))
        panel.contentView = host

        // Build SwiftUI's machinery now, not on the first Alt-Tab.
        host.layoutSubtreeIfNeeded()

        // The index resolves a point against the panel it came from: three
        // screens means three coordinate spaces holding the same picture.
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
        // The router has already set isOverlayVisible, so a silent return here
        // leaves it swallowing arrows and escape system-wide until the modifier
        // comes back up.
        guard let bundleID = frontmost.bundleID else {
            onUnexpectedClose?()
            return
        }

        open(.application(bundleID), step: step)
    }

    func reachApplication(_ bundleID: String) {
        let windows = store.windows(
            ofBundleID: bundleID, includingMinimized: true, fromEverySpace: everySpace
        )

        // activate() brings the application forward but leaves its windows in
        // the Dock, so one with only minimised windows would show nothing.
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

        model.selected = Self.step(from: model.selected, by: step, of: model.windows.count)
        anchorPointer()
    }

    /// Where opening lands, which is one step on from the window in front.
    private func selectedIndex(for count: Int, step: Int) -> Int {
        Self.step(from: 0, by: step, of: count)
    }

    private static func step(from index: Int, by step: Int, of count: Int) -> Int {
        guard count > 0 else { return 0 }

        return (index + step % count + count) % count
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

        // The application is public, the title is not: Copy Diagnostics puts the
        // recent log into a report meant for a GitHub issue, and for a window
        // switcher a title is a document name or a mail subject.
        log.debug("focusing \(window.applicationName, privacy: .public) — \(window.title, privacy: .private)")
        store.focus(window)
    }

    func cancel() {
        guard isVisible else { return }

        hide()
    }

    // MARK: - Mouse

    /// Hovering waits for the pointer to actually move: a grid opening under a
    /// resting pointer must not discard the keyboard's selection.
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

        // The router decides synchronously and cannot see the click, so it would
        // keep swallowing keys until the leader is let go.
        defer { onUnexpectedClose?() }

        // Outside the grid is backdrop, not a tile: give up rather than commit.
        guard let tile = tile(at: point, on: panelIndex) else { return cancel() }

        model.selected = tile
        commit()
    }

    /// The grid is centred in the panel the point came from, so that panel's
    /// size is the container the hit test needs.
    private func tile(at point: CGPoint, on panelIndex: Int) -> Int? {
        model.layout.index(
            at: point, in: panels[panelIndex].frame.size, count: model.windows.count
        )
    }

    /// In screen coordinates, so it spans however many displays the grid is on.
    private func anchorPointer() {
        pointerAnchor = NSEvent.mouseLocation
    }

    // MARK: - Internals

    /// Which question the overlay answers. Changing it narrows an open overlay
    /// rather than stepping it along.
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

            // Narrowing to nothing leaves the overlay standing; only a failed
            // open is reported, or the router keeps swallowing keys.
            if !isVisible { onUnexpectedClose?() }
            return
        }

        let wasVisible = isVisible

        // Opening steps onto the previous window; narrowing does not, since the
        // application was named and its top window is the answer. Worked out
        // before presenting, so the captures are ordered around the tile that
        // ends up selected rather than around index 0.
        let selection = wasVisible ? 0 : selectedIndex(for: windows.count, step: step)
        present(windows, from: source, selecting: selection)

        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000
        log.notice("""
        \(wasVisible ? "narrowed" : "opened", privacy: .public) to \
        \(windows.count, privacy: .public) windows \
        in \(String(format: "%.2f", elapsed), privacy: .public)ms, \
        \(self.model.thumbnails.count, privacy: .public) thumbnails ready
        """)
    }

    private func present(_ windows: [WindowInfo], from source: Source, selecting selected: Int) {
        let screens = targetScreens()
        ensurePanels(screens.count)

        // Laid out for the narrowest, so one grid fits every screen it is on.
        let narrowest = screens.min { $0.frame.width < $1.frame.width } ?? screens[0]

        model.windows = windows
        model.selected = selected
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

        // Narrowing keeps what the session decided, so pressing a key while
        // holding the leader does not restart the wait — and the same goes for
        // the lifetime guard, which measures from when the modifier went down.
        // Re-arming it here left the first timer in the runloop, still able to
        // close a session started half a minute later.
        if !wasRunning {
            scheduleReveal()
            scheduleLifetime()
        }

        if panels.prefix(inUse).contains(where: \.isVisible) {
            requestMissingThumbnails(for: windows)
        }
    }

    private func scheduleLifetime() {
        lifetime = Timer.scheduledTimer(withTimeInterval: Configuration.maxOverlayLifetime, repeats: false) { _ in
            MainActor.assumeIsolated { [weak self] in
                guard let self, isVisible else { return }

                log.error("overlay outlived its welcome; closing")
                hide()
                onUnexpectedClose?()
            }
        }
    }

    /// The selection exists but nothing is drawn. Releasing the leader from
    /// here is the fast path the delay is for.
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
