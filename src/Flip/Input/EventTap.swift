import CoreGraphics
import Foundation
import OSLog

/// A session-wide keyboard tap on its own thread. macOS quietly disables a tap
/// whose callback misses its deadline, so it must never queue behind main.
final class EventTap {
    /// Returning nil swallows the event.
    typealias Handler = (CGEventType, CGEvent) -> CGEvent?

    private let mask: CGEventMask
    private let handler: Handler
    private let log = Logger(subsystem: Bundle.identifier, category: "eventtap")

    /// Written on the tap's thread, read from the main one when pausing.
    private let state = NSLock()
    private var port: CFMachPort?
    private var runLoop: CFRunLoop?

    /// Whether the tap is meant to run. A deliberate disable looks exactly like
    /// a missed deadline, so without this the recovery would undo the pause.
    private var wanted = true

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

    /// At the port, not in the handler: while paused the events never reach
    /// Flip at all, so the Dock gets Cmd-Tab back.
    func setEnabled(_ enabled: Bool) {
        state.lock()
        wanted = enabled
        let port = port
        state.unlock()

        guard let port else { return }

        CGEvent.tapEnable(tap: port, enable: enabled)
        log.notice("tap \(enabled ? "enabled" : "disabled", privacy: .public)")
    }

    func stop() {
        state.lock()
        wanted = false
        let port = port
        let runLoop = runLoop
        state.unlock()

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
            // The call gives no reason; a missing Accessibility grant is usual.
            log.error("could not create the event tap; is Accessibility granted?")
            return
        }

        state.lock()
        self.port = port
        runLoop = CFRunLoopGetCurrent()
        state.unlock()

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)

        log.notice("event tap running on its own thread")
        CFRunLoopRun()
    }

    private func dispatch(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // Announced once. Without re-enabling, every hotkey silently dies until
        // restart — but a pause looks identical here, so intent decides.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            state.lock()
            let recover = wanted
            let port = port
            state.unlock()

            guard recover, let port else { return Unmanaged.passUnretained(event) }

            log.error("tap was disabled (\(type == .tapDisabledByTimeout ? "timeout" : "user input", privacy: .public)); re-enabling")
            CGEvent.tapEnable(tap: port, enable: true)

            return Unmanaged.passUnretained(event)
        }

        guard let result = handler(type, event) else { return nil }

        return Unmanaged.passUnretained(result)
    }
}
