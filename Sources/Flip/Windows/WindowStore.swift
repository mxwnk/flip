import AppKit
import ApplicationServices
import CoreGraphics
import OSLog

/// The live window model.
///
/// This is the heart of the rewrite. Hammerspoon rebuilt its view of the world by
/// asking the accessibility API, which is why it needed a cache and why a busy
/// application could stall it. Here the model is maintained continuously by
/// notifications on a thread of its own, and opening the switcher costs one lock
/// and one window server call — no accessibility traffic at all.
final class WindowStore: @unchecked Sendable {
    private let log = Logger(subsystem: Bundle.identifier, category: "windows")
    private let thread = RunLoopThread(name: "\(Bundle.identifier).windows")

    /// Everything below is owned by `thread` and must not be touched elsewhere.
    private var watchers: [pid_t: AXApplicationWatcher] = [:]
    private var windows: [CGWindowID: WindowInfo] = [:]
    private var focusCounter: UInt64 = 0

    /// The published copy, in most-recently-focused order. Read from the main
    /// thread when the switcher opens.
    private let lock = NSLock()
    private var snapshot: [WindowInfo] = []

    // MARK: - Reading

    /// Windows on the current space, most recently focused first.
    ///
    /// Minimised windows are not on screen and so are not in the window server's
    /// listing; the accessibility model is the only record that they exist, which
    /// is why they are added back rather than filtered in.
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

    /// Raising is an accessibility call and belongs on the store's thread with
    /// everything else; only bringing the application forward is main-thread work.
    func focus(_ window: WindowInfo) {
        thread.perform { [self] in
            guard window.isMinimized else { return raise(window) }

            AXUIElementSetAttributeValue(
                window.element, kAXMinimizedAttribute as CFString, kCFBooleanFalse
            )

            // Unminimising is asynchronous — the window animates out of the Dock
            // first — and a raise issued in the same breath is dropped.
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.15) { [self] in
                thread.perform { self.raise(window) }
            }
        }
    }

    private func raise(_ window: WindowInfo) {
        // Two separate things: main makes it the application's window, raise puts
        // it in front of that application's other windows.
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

        // NSWorkspace is main-thread API, so the applications are collected here
        // and only their identities cross over to the accessibility thread.
        let running = NSWorkspace.shared.runningApplications.compactMap(Identity.init)
        thread.perform { [self] in
            running.forEach(adopt)
            seedFocusOrderFromScreenOrder()
            publish()
            log.notice("watching \(self.watchers.count, privacy: .public) applications, \(self.windows.count, privacy: .public) windows")
        }

        observeWorkspace()
    }

    /// What crosses from the main thread to the accessibility thread.
    private struct Identity {
        let pid: pid_t
        let bundleID: String?
        let name: String

        init?(_ application: NSRunningApplication) {
            // Agents and background helpers own no windows and would only add
            // observers that never fire.
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

        // Switching applications reorders the list even when no window-level
        // notification fires, so activation is a focus event in its own right.
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

        // An application that has just launched is often not ready to answer
        // accessibility calls yet. Its windows arrive by notification later, and
        // if even the observer cannot be created it is simply not watched.
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
            update(element) { [self] in
                focusCounter += 1
                $0.focusOrder = focusCounter
            }
        }

        publish()
    }

    @discardableResult
    private func insert(_ element: AXUIElement, from watcher: AXApplicationWatcher) -> Bool {
        guard AXBridge.isStandardWindow(element), let id = AXBridge.windowID(of: element)
        else { return false }

        // Titles, minimising and closing are all announced by the window rather
        // than by the application, so each window has to be subscribed to.
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

    /// A destroyed element can no longer be asked for its window ID, so the entry
    /// has to be found by identity instead.
    private func remove(_ element: AXUIElement) {
        guard let id = windows.first(where: { CFEqual($0.value.element, element) })?.key
        else { return }

        windows[id] = nil
    }

    private func update(_ element: AXUIElement, _ change: (inout WindowInfo) -> Void) {
        guard let id = AXBridge.windowID(of: element) else { return }

        // A window can be announced before it was ever listed, for instance when
        // an application was still launching when its watcher was created.
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

        update(focused) { [self] in
            focusCounter += 1
            $0.focusOrder = focusCounter
        }
    }

    /// Nothing has been focused yet at startup, so the window server's front-to-back
    /// order stands in: it is the closest thing to a focus history that exists.
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
