import AppKit
import ApplicationServices
import CoreGraphics
import OSLog

/// The live window model, kept by AXObserver notifications on its own thread.
/// Reading it costs one lock and one window server call, no AX traffic.
final class WindowStore: @unchecked Sendable {
    private let log = Logger(subsystem: Bundle.identifier, category: "windows")
    private let thread = RunLoopThread(name: "\(Bundle.identifier).windows")

    /// Owned by `thread`. Not to be touched elsewhere.
    private var watchers: [pid_t: AXApplicationWatcher] = [:]
    private var windows: [CGWindowID: WindowInfo] = [:]
    private var focusCounter: UInt64 = 0
    private var lastFocusedID: CGWindowID?
    /// Cocoa coordinates, for the fill toggle. Cleared when the window goes.
    private var restoreFrames: [CGWindowID: CGRect] = [:]

    /// The cheapest moment to capture a thumbnail: content final, still on screen.
    var onWindowDefocused: ((CGWindowID) -> Void)?

    /// Most-recently-focused order, read from the main thread.
    private let lock = NSLock()
    private var snapshot: [WindowInfo] = []

    // MARK: - Reading

    /// Minimised windows are in neither window server listing, so they come from
    /// the AX model instead and cannot obey the space filter.
    func windows(
        ofBundleID bundleID: String? = nil,
        includingMinimized: Bool = false,
        fromEverySpace: Bool = false
    ) -> [WindowInfo] {
        let listing = fromEverySpace ? ScreenWindows.everySpace() : ScreenWindows.onCurrentSpace()
        let onScreen = Set(listing.map(\.id))

        lock.lock()
        let all = snapshot
        lock.unlock()

        return all.filter { window in
            if let bundleID, window.bundleID != bundleID { return false }
            if window.isMinimized { return includingMinimized }

            return onScreen.contains(window.id)
        }
    }

    /// From the published snapshot: a lock, no accessibility traffic.
    func size(of id: CGWindowID) -> CGSize? {
        lock.lock()
        defer { lock.unlock() }

        return snapshot.first { $0.id == id }?.frame.size
    }

    // MARK: - Focusing

    func focus(_ window: WindowInfo) {
        thread.perform { [self] in
            guard window.isMinimized else { return raise(window) }

            AXUIElementSetAttributeValue(
                window.element, kAXMinimizedAttribute as CFString, kCFBooleanFalse
            )

            // Unminimising animates out of the Dock; a raise now is dropped.
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.15) { [self] in
                thread.perform { self.raise(window) }
            }
        }
    }

    private func raise(_ window: WindowInfo) {
        AXUIElementSetAttributeValue(window.element, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementPerformAction(window.element, kAXRaiseAction as CFString)

        let pid = window.pid
        DispatchQueue.main.async {
            NSRunningApplication(processIdentifier: pid)?.activate()
        }
    }

    /// The window's own close button is the only close accessibility offers.
    /// The application still decides what closing means.
    func close(_ window: WindowInfo) {
        thread.perform { [self] in
            guard let button = AXBridge.element(kAXCloseButtonAttribute as String, of: window.element)
            else { return log.debug("no close button on \(window.applicationName, privacy: .public)") }

            AXUIElementPerformAction(button, kAXPressAction as CFString)
        }
    }

    /// Reads on the accessibility thread, computes on main where NSScreen lives,
    /// writes back. Two hops, neither framework touched from the wrong one.
    func arrange(_ arrangement: WindowArrangement) {
        thread.perform { [self] in
            guard let (id, element) = focusedWindow() else { return }

            // In native full screen the frame cannot be written; the window owns
            // its space. Only the fill key leaves it — the halves would have to
            // wait out the space animation.
            if arrangement == .maximize,
               AXBridge.bool(AXBridge.fullScreenAttribute, of: element) == true {
                AXBridge.setBool(false, AXBridge.fullScreenAttribute, of: element)
                return
            }

            guard let current = AXBridge.frame(of: element) else { return }

            let remembered = restoreFrames[id]

            // Only the geometry needs main; NSScreen is unsafe elsewhere.
            DispatchQueue.main.async { [self] in
                guard let cocoa = ScreenGeometry.cocoa(fromTopLeft: current) else { return }

                let outcome = WindowArranger.outcome(
                    for: arrangement, window: cocoa, remembered: remembered
                )
                guard let target = outcome.target,
                      let topLeft = ScreenGeometry.topLeft(fromCocoa: target)
                else { return }

                thread.perform { [self] in
                    AXBridge.setFrame(topLeft, of: element)
                    restoreFrames[id] = outcome.restore
                }
            }
        }
    }

    private func focusedWindow() -> (id: CGWindowID, element: AXUIElement)? {
        if let id = lastFocusedID, let window = windows[id] { return (id, window.element) }

        guard let window = windows.values.max(by: { $0.focusOrder < $1.focusOrder })
        else { return nil }

        return (window.id, window.element)
    }

    // MARK: - Lifecycle

    @MainActor
    func start() {
        thread.start()

        let running = NSWorkspace.shared.runningApplications.compactMap(Identity.init)
        thread.perform { [self] in
            running.forEach(adopt)
            seedFocusOrderFromScreenOrder()
            publish()
            log.notice("watching \(self.watchers.count, privacy: .public) applications, \(self.windows.count, privacy: .public) windows")
        }

        observeWorkspace()
    }

    private struct Identity {
        let pid: pid_t
        let bundleID: String?
        let name: String

        init?(_ application: NSRunningApplication) {
            // Agents own no windows; observers on them never fire.
            guard application.activationPolicy == .regular else { return nil }

            pid = application.processIdentifier
            bundleID = application.bundleIdentifier
            name = application.localizedName ?? application.bundleIdentifier ?? "?"
        }
    }

    @MainActor
    private func observeWorkspace() {
        let center = NSWorkspace.shared.notificationCenter
        let key = NSWorkspace.applicationUserInfoKey

        center.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in
            guard let application = notification.userInfo?[key] as? NSRunningApplication,
                  let identity = Identity(application) else { return }

            self?.thread.perform { self?.adopt(identity); self?.publish() }
        }

        center.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in
            guard let application = notification.userInfo?[key] as? NSRunningApplication
            else { return }

            let pid = application.processIdentifier
            self?.thread.perform { self?.drop(pid); self?.publish() }
        }

        // Accessibility lists only the current space. A held element stays valid
        // afterwards and raising it switches spaces, so learning the set as you
        // move around needs no private call.
        center.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.thread.perform { self?.adoptWindowsRevealedByTheCurrentSpace() }
        }

        // Activation reorders the list even when no window notification fires.
        center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in
            guard let application = notification.userInfo?[key] as? NSRunningApplication
            else { return }

            let pid = application.processIdentifier
            self?.thread.perform { self?.promoteFocusedWindow(of: pid); self?.publish() }
        }
    }

    // MARK: - Maintaining the model (accessibility thread only)

    private func adopt(_ identity: Identity) {
        guard watchers[identity.pid] == nil else { return }

        let watcher = AXApplicationWatcher(
            pid: identity.pid,
            bundleID: identity.bundleID,
            name: identity.name
        ) { [weak self] watcher, event, element in
            self?.handle(event, from: watcher, element: element)
        }

        // A launching application may not answer AX yet; its windows arrive later.
        guard let runLoop = thread.cfRunLoop, watcher.start(on: runLoop) else { return }

        watchers[identity.pid] = watcher
        for element in watcher.windows() {
            insert(element, from: watcher)
        }
    }

    /// New windows only: re-inserting resets the most-recently-used order.
    private func adoptWindowsRevealedByTheCurrentSpace() {
        var found = 0
        for watcher in watchers.values {
            for element in watcher.windows() {
                guard let id = AXBridge.windowID(of: element), windows[id] == nil else { continue }
                if insert(element, from: watcher) { found += 1 }
            }
        }

        guard found > 0 else { return }

        log.notice("this space revealed \(found, privacy: .public) windows not seen before")
        publish()
    }

    private func drop(_ pid: pid_t) {
        watchers[pid] = nil

        // The frames go too: window server ids are reused, and a stale one would
        // put a fill back onto a dead window's place.
        for (id, window) in windows where window.pid == pid { restoreFrames[id] = nil }
        windows = windows.filter { $0.value.pid != pid }
    }

    private func handle(_ event: AXApplicationWatcher.Event, from watcher: AXApplicationWatcher, element: AXUIElement) {
        switch event {
        case .windowCreated:
            insert(element, from: watcher)
        case .elementDestroyed:
            remove(element)
        case .titleChanged:
            update(element) { $0.title = AXBridge.string(kAXTitleAttribute as String, of: element) ?? $0.title }
        case .minimized:
            update(element) { $0.isMinimized = true }
        case .deminimized:
            update(element) { $0.isMinimized = false }
        case .focused:
            markFocused(element)
        }

        publish()
    }

    @discardableResult
    private func insert(_ element: AXUIElement, from watcher: AXApplicationWatcher) -> Bool {
        guard AXBridge.isStandardWindow(element), let id = AXBridge.windowID(of: element)
        else { return false }

        // Titles, minimising and closing are announced by the window, not the app.
        watcher.observe(window: element)

        windows[id] = WindowInfo(
            id: id,
            element: element,
            pid: watcher.pid,
            bundleID: watcher.bundleID,
            applicationName: watcher.name,
            title: AXBridge.string(kAXTitleAttribute as String, of: element) ?? "",
            isMinimized: AXBridge.bool(kAXMinimizedAttribute as String, of: element) ?? false,
            frame: AXBridge.frame(of: element) ?? .zero,
            focusOrder: 0
        )

        return true
    }

    /// A destroyed element has no window ID left, so it is found by identity.
    private func remove(_ element: AXUIElement) {
        guard let id = windows.first(where: { CFEqual($0.value.element, element) })?.key
        else { return }

        windows[id] = nil
        restoreFrames[id] = nil
    }

    private func update(_ element: AXUIElement, _ change: (inout WindowInfo) -> Void) {
        guard let id = AXBridge.windowID(of: element) else { return }

        // A window can be announced before it was ever listed.
        if windows[id] == nil {
            var pid: pid_t = 0
            guard AXUIElementGetPid(element, &pid) == .success,
                  let watcher = watchers[pid],
                  insert(element, from: watcher)
            else { return }
        }

        change(&windows[id]!)
    }

    private func promoteFocusedWindow(of pid: pid_t) {
        guard let focused = watchers[pid]?.focusedWindow() else { return }

        markFocused(focused)
    }

    private func markFocused(_ element: AXUIElement) {
        update(element) { [self] in
            focusCounter += 1
            $0.focusOrder = focusCounter
        }

        guard let id = AXBridge.windowID(of: element), id != lastFocusedID else { return }

        if let previous = lastFocusedID { onWindowDefocused?(previous) }
        lastFocusedID = id
    }

    func allWindowIDs() -> [CGWindowID] {
        lock.lock()
        defer { lock.unlock() }

        return snapshot.filter { !$0.isMinimized }.map(\.id)
    }

    /// Nothing is focused yet at startup, so front-to-back order stands in.
    private func seedFocusOrderFromScreenOrder() {
        let onScreen = ScreenWindows.onCurrentSpace()

        for entry in onScreen.reversed() where windows[entry.id] != nil {
            focusCounter += 1
            windows[entry.id]?.focusOrder = focusCounter
        }
    }

    private func publish() {
        let sorted = windows.values.sorted { $0.focusOrder > $1.focusOrder }

        lock.lock()
        snapshot = sorted
        lock.unlock()
    }
}
