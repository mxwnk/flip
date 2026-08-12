import AppKit
import OSLog
import SwiftUI

/// Panels are built once at launch and never torn down, one per screen: showing
/// one is an `orderFront`, hiding it an `orderOut`.
@MainActor
final class OverlayPresenter: SwitcherPresenting {
    private let log = Logger(subsystem: Bundle.identifier, category: "switcher")
    private let store: WindowStore
    private let frontmost: FrontmostApp
    private let thumbnails: ThumbnailStore
    private let settings: SettingsStore

    private let model = OverlayModel()
    private var panels: [NSPanel] = []
    private var inUse = 0
    /// A session is running. The panel may not be drawn: a tap released inside
    /// the delay commits without showing anything.
    private var isVisible = false
    private var currentSource: Source?
    private var lifetime: Timer?
    private var reveal: Timer?
    /// Hovering is ignored until the pointer moves away from here.
    private var pointerAnchor: CGPoint?
    /// Kept so a tile leaving mid-session can relayout without asking the
    /// screens again.
    private var gridScreen: CGSize = .zero

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

        // The panel and its SwiftUI machinery are the expensive part; not
        // paying for them at ⌥Tab is what the design is arranged around.
        ensurePanels(max(NSScreen.screens.count, 1))
    }

    private func ensurePanels(_ count: Int) {
        while panels.count < count { panels.append(makePanel(index: panels.count)) }
    }

    private func makePanel(index: Int) -> NSPanel {
        let panel = NSPanel(
            contentRect: NSScreen.main?.frame ?? .zero,
            // The switcher must not become the application it switches away from.
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
        // overlay lands at level 3, under the menu bar and full-screen windows.
        panel.isFloatingPanel = true
        panel.level = .screenSaver
        // Clicks on the dimmed backdrop cancel; see `click`.
        panel.ignoresMouseEvents = false
        panel.acceptsMouseMovedEvents = true

        let host = OverlayHostingView(rootView: OverlayView(model: model))
        panel.contentView = host

        host.layoutSubtreeIfNeeded()

        // Three screens are three coordinate spaces holding the same picture.
        host.onPointerMoved = { [weak self] point in self?.hover(at: point, on: index) }
        host.onClick = { [weak self] point in self?.click(at: point, on: index) }
        host.onScroll = { [weak self] steps in self?.scroll(by: steps, on: index) }

        return panel
    }

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
        // The router already set isOverlayVisible; a silent return leaves it
        // swallowing arrows and escape system-wide.
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

        // activate() leaves minimised windows in the Dock, so an application
        // with only those would come forward showing nothing.
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

        // The title stays private: Copy Diagnostics pastes this log into an
        // issue, and a window title is a document name or a mail subject.
        log.debug("focusing \(window.applicationName, privacy: .public) — \(window.title, privacy: .private)")
        store.focus(window)
    }

    func cancel() {
        guard isVisible else { return }

        hide()
    }

    func closeSelection() {
        guard isVisible, model.windows.indices.contains(model.selected) else { return }

        let window = model.windows[model.selected]
        log.debug("closing \(window.applicationName, privacy: .public) — \(window.title, privacy: .private)")
        store.close(window)

        // Now, not when the destroyed notification reaches the store, so the
        // grid keeps up with the keystroke.
        var remaining = model.windows
        remaining.remove(at: model.selected)

        guard !remaining.isEmpty else {
            hide()
            onUnexpectedClose?()
            return
        }

        model.windows = remaining
        // Onto the tile that moved up into the gap, or the new last one.
        model.selected = min(model.selected, remaining.count - 1)
        model.layout = OverlayLayout(count: remaining.count, screen: gridScreen)
        anchorPointer()
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

    /// Through `move`, which also re-anchors the pointer: otherwise a hover
    /// the wheel itself caused would take the selection straight back.
    private func scroll(by steps: Int, on panelIndex: Int) {
        guard isVisible, panelIndex < inUse, panels[panelIndex].isVisible else { return }

        move(by: steps)
    }

    private func click(at point: CGPoint, on panelIndex: Int) {
        guard isVisible, panelIndex < inUse, panels[panelIndex].isVisible else { return }

        // The router cannot see the click and would keep swallowing keys.
        defer { onUnexpectedClose?() }

        // Outside the grid is backdrop, not a tile: give up rather than commit.
        guard let tile = tile(at: point, on: panelIndex) else { return cancel() }

        model.selected = tile
        commit()
    }

    /// The grid is centred in its panel, so that panel is the hit test's box.
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

    /// Changing it narrows an open overlay rather than stepping it along.
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
        // Same question: walk the list, do not rebuild it under the selection.
        if isVisible, currentSource == source {
            move(by: step)
            return
        }

        let started = DispatchTime.now().uptimeNanoseconds
        let windows = windows(for: source)

        guard !windows.isEmpty else {
            log.debug("nothing to show for \(String(describing: source), privacy: .public)")

            // Only a failed open is reported, or the router keeps swallowing keys.
            if !isVisible { onUnexpectedClose?() }
            return
        }

        let wasVisible = isVisible

        // Opening steps onto the previous window; narrowing does not. Decided
        // before presenting, so captures are ordered around the real selection.
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
        gridScreen = narrowest.frame.size

        model.windows = windows
        model.selected = selected
        model.layout = OverlayLayout(count: windows.count, screen: gridScreen)
        model.thumbnails = alreadyCaptured(windows)

        for (index, screen) in screens.enumerated() {
            panels[index].setFrame(screen.frame, display: false)
        }
        inUse = screens.count

        let wasRunning = isVisible
        isVisible = true
        currentSource = source
        anchorPointer()

        // Both belong to the session, not to each present() within it: the
        // lifetime guard measures from when the modifier went down, and
        // re-arming it would leave the first timer armed in the runloop.
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

    /// Selection made, nothing drawn — the fast path the delay exists for.
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
