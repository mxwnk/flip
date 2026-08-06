import AppKit
import ApplicationServices
import CoreGraphics
import OSLog

/// The live window model, maintained by AXObserver notifications on its own
/// thread. Reading it costs one lock and one window server call, no AX traffic.
final class WindowStore: @unchecked Sendable {
    private let log = Logger(subsystem: Bundle.identifier, category: "windows")
    private let thread = RunLoopThread(name: "\(Bundle.identifier).windows")

    /// Everything below is owned by `thread` and must not be touched elsewhere.
    private var watchers: [pid_t: AXApplicationWatcher] = [:]
    private var windows: [CGWindowID: WindowInfo] = [:]
    private var focusCounter: UInt64 = 0
    private var lastFocusedID: CGWindowID?

    /// The cheapest moment to capture a thumbnail: content final, still on screen.
    var onWindowDefocused: ((CGWindowID) -> Void)?

    /// Most-recently-focused order, read from the main thread.
    private let lock = NSLock()
    private var snapshot: [WindowInfo] = []

    // MARK: - Reading

    /// Minimised windows are absent from the window server listing, so they are
    /// added back from the AX model rather than filtered in.
    func currentSpaceWindows(
        ofBundleID bundleID: String? = nil,
        includingMinimized: Bool = false
    ) -> [WindowInfo] {
        let onScreen = Set(ScreenWindows.onCurrentSpace().map(\.id))

        lock.lock()
        let all = snapshot
        lock.unlock()

        return all.filter { window in
            if let bundleID, window.bundleID != bundleID { return false }
            if window.isMinimized { return includingMinimized }

            return onScreen.contains(window.id)
        }
    }

    // MARK: - Focusing

    func focus(_ window: WindowInfo) {
        thread.perform { [self] in
            guard window.isMinimized else { return raise(window) }

            AXUIElementSetAttributeValue(
                window.element, kAXMinimizedAttribute as CFString, kCFBooleanFalse
            )

            // Unminimising animates out of the Dock; a raise in the same breath
            // is dropped.
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

        // A launching application may not answer AX yet; its windows arrive by
        // notification later.
        guard let runLoop = thread.cfRunLoop, watcher.start(on: runLoop) else { return }

        watchers[identity.pid] = watcher
        for element in watcher.windows() {
            insert(element, from: watcher)
        }
    }

    private func drop(_ pid: pid_t) {
        watchers[pid] = nil
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
            focusOrder: 0
        )

        return true
    }

    /// A destroyed element has no window ID left, so it is found by identity.
    private func remove(_ element: AXUIElement) {
        guard let id = windows.first(where: { CFEqual($0.value.element, element) })?.key
        else { return }

        windows[id] = nil
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

    /// Nothing has been focused yet at startup, so front-to-back order stands in.
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
