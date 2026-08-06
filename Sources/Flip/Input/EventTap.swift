import CoreGraphics
import Foundation
import OSLog

/// A session-wide keyboard tap on a thread of its own. macOS quietly disables a
/// tap whose callback misses its deadline, so it must never queue behind the main
/// thread's rendering and window server round trips.
final class EventTap {
    /// Returning nil swallows the event.
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
        // Unretained: the delegate owns the tap, and retaining here would cycle.
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
            // The call gives no reason; a missing Accessibility grant is the usual one.
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
        // Announced exactly once. Without re-enabling, every hotkey silently stops
        // working until the app restarts.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            log.error("tap was disabled (\(type == .tapDisabledByTimeout ? "timeout" : "user input", privacy: .public)); re-enabling")
            if let port { CGEvent.tapEnable(tap: port, enable: true) }

            return Unmanaged.passUnretained(event)
        }

        guard let result = handler(type, event) else { return nil }

        return Unmanaged.passUnretained(result)
    }
}
