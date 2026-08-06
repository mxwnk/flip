import ApplicationServices
import Foundation

/// Watches one application's windows. One observer per application is the only
/// shape the API offers: AXObserverCreate takes a pid.
final class AXApplicationWatcher: @unchecked Sendable {
    enum Event {
        case windowCreated
        case elementDestroyed
        case titleChanged
        case minimized
        case deminimized
        case focused
    }

    let pid: pid_t
    let bundleID: String?
    let name: String
    let element: AXUIElement

    private var observer: AXObserver?
    private let onEvent: (AXApplicationWatcher, Event, AXUIElement) -> Void

    /// Registering everything on the application element looks like it works —
    /// windows appear, focus tracks — but titles then never update, because a
    /// title change is delivered to the window that owns it.
    private static let applicationSubscriptions: [(name: String, event: Event)] = [
        (kAXWindowCreatedNotification, .windowCreated),
        (kAXFocusedWindowChangedNotification, .focused),
    ]

    /// Announced by the window itself.
    private static let windowSubscriptions: [(name: String, event: Event)] = [
        (kAXTitleChangedNotification, .titleChanged),
        (kAXUIElementDestroyedNotification, .elementDestroyed),
        (kAXWindowMiniaturizedNotification, .minimized),
        (kAXWindowDeminiaturizedNotification, .deminimized),
    ]

    init(
        pid: pid_t,
        bundleID: String?,
        name: String,
        onEvent: @escaping (AXApplicationWatcher, Event, AXUIElement) -> Void
    ) {
        self.pid = pid
        self.bundleID = bundleID
        self.name = name
        self.element = AXUIElementCreateApplication(pid)
        self.onEvent = onEvent
    }

    deinit {
        guard let observer else { return }
        CFRunLoopSourceInvalidate(AXObserverGetRunLoopSource(observer))
    }

    /// False for applications with no accessibility interface at all.
    @discardableResult
    func start(on runLoop: CFRunLoop) -> Bool {
        // An application that never answers must not hold this thread for the
        // six second default.
        AXBridge.limitMessagingTimeout(of: element)

        var created: AXObserver?
        guard AXObserverCreate(pid, callback, &created) == .success, let observer = created
        else { return false }

        let context = Unmanaged.passUnretained(self).toOpaque()
        for subscription in Self.applicationSubscriptions {
            AXObserverAddNotification(observer, element, subscription.name as CFString, context)
        }

        CFRunLoopAddSource(runLoop, AXObserverGetRunLoopSource(observer), .defaultMode)
        self.observer = observer

        return true
    }

    /// Registrations die with the element, so closed windows need no cleanup.
    func observe(window: AXUIElement) {
        guard let observer else { return }

        let context = Unmanaged.passUnretained(self).toOpaque()
        for subscription in Self.windowSubscriptions {
            AXObserverAddNotification(observer, window, subscription.name as CFString, context)
        }
    }

    func windows() -> [AXUIElement] {
        AXBridge.elements(kAXWindowsAttribute as String, of: element)
    }

    func focusedWindow() -> AXUIElement? {
        AXBridge.element(kAXFocusedWindowAttribute as String, of: element)
    }

    fileprivate func deliver(_ notification: String, from element: AXUIElement) {
        let subscriptions = Self.applicationSubscriptions + Self.windowSubscriptions
        guard let event = subscriptions.first(where: { $0.name == notification })?.event
        else { return }

        onEvent(self, event, element)
    }
}

/// A bare C function pointer, so the watcher travels through the refcon.
private let callback: AXObserverCallback = { _, element, notification, context in
    guard let context else { return }

    Unmanaged<AXApplicationWatcher>.fromOpaque(context)
        .takeUnretainedValue()
        .deliver(notification as String, from: element)
}
