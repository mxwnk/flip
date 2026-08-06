import CoreGraphics
import Foundation
import OSLog

/// A session-wide keyboard tap running on a thread of its own.
///
/// The dedicated thread is the point. macOS gives a tap callback a deadline and
/// quietly disables the tap when it is missed, so the callback must never queue
/// behind anything slow — and the main thread is exactly where rendering, AppKit
/// and every window server round trip live. The Hammerspoon version could not
/// separate the two: its tap shared a runloop with all of that, so a busy moment
/// anywhere delayed the keyboard everywhere.
final class EventTap {
    /// Returning nil swallows the event. Called on the tap's own thread.
    typealias Handler = (CGEventType, CGEvent) -> CGEvent?

    private let mask: CGEventMask
    private let handler: Handler
    private let log = Logger(subsystem: Bundle.identifier, category: "eventtap")

    private var port: CFMachPort?
    private var runLoop: CFRunLoop?

    init(observing types: [CGEventType], handler: @escaping Handler) {
        self.mask = types.reduce(into: CGEventMask(0)) { $0 |= 1 << CGEventMask($1.rawValue) }
        self.handler = handler
    }

    func start() {
        let thread = Thread { [weak self] in self?.run() }
        thread.name = "\(Bundle.identifier).eventtap"
        thread.qualityOfService = .userInteractive
        thread.start()
    }

    func stop() {
        if let port { CGEvent.tapEnable(tap: port, enable: false) }
        if let runLoop { CFRunLoopStop(runLoop) }
    }

    private func run() {
        // Unretained on purpose: the tap outlives every event it sees, and the app
        // delegate owns it. Retaining here would make the cycle permanent.
        let context = Unmanaged.passUnretained(self).toOpaque()

        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, context in
                guard let context else { return Unmanaged.passUnretained(event) }

                return Unmanaged<EventTap>.fromOpaque(context)
                    .takeUnretainedValue()
                    .dispatch(type: type, event: event)
            },
            userInfo: context
        ) else {
            // The only realistic cause is a missing Accessibility grant, and the
            // call gives no reason of its own.
            log.error("could not create the event tap; is Accessibility granted?")
            return
        }

        self.port = port
        runLoop = CFRunLoopGetCurrent()

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)

        log.notice("event tap running on its own thread")
        CFRunLoopRun()
    }

    private func dispatch(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // A tap that misses its deadline is switched off and announced exactly
        // once. Without turning it back on, every hotkey stops working until the
        // app is restarted — silently.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            log.error("tap was disabled (\(type == .tapDisabledByTimeout ? "timeout" : "user input", privacy: .public)); re-enabling")
            if let port { CGEvent.tapEnable(tap: port, enable: true) }

            return Unmanaged.passUnretained(event)
        }

        guard let result = handler(type, event) else { return nil }

        return Unmanaged.passUnretained(result)
    }
}
