import Foundation

/// A thread that owns a CFRunLoop, for work that must never touch the main one.
///
/// Accessibility observers deliver notifications to whichever runloop their source
/// was added to, and every read they provoke is a synchronous round trip into
/// another process. Put that on the main thread — as the Hammerspoon version had
/// no choice but to — and a single unresponsive application freezes the interface
/// for as long as it takes to time out.
final class RunLoopThread: @unchecked Sendable {
    private let name: String
    private let ready = DispatchSemaphore(value: 0)
    private var runLoop: CFRunLoop?

    init(name: String) {
        self.name = name
    }

    /// Returns once the runloop exists, so callers can enqueue work immediately.
    func start() {
        let thread = Thread { [self] in
            runLoop = CFRunLoopGetCurrent()
            ready.signal()

            // A runloop with no sources exits straight away, and the observer
            // sources only arrive later, so one port is kept installed to hold it
            // open for the lifetime of the process.
            RunLoop.current.add(NSMachPort(), forMode: .default)
            CFRunLoopRun()
        }

        thread.name = name
        thread.qualityOfService = .userInitiated
        thread.start()
        ready.wait()
    }

    func perform(_ block: @escaping () -> Void) {
        guard let runLoop else { return }

        CFRunLoopPerformBlock(runLoop, CFRunLoopMode.defaultMode.rawValue, block)
        CFRunLoopWakeUp(runLoop)
    }

    /// Where AXObserver sources are attached.
    var cfRunLoop: CFRunLoop? { runLoop }
}
