import Foundation

/// A thread owning a CFRunLoop, for accessibility work. AX observers deliver to
/// whichever runloop their source joined, and every read they provoke is a
/// synchronous round trip into another process.
final class RunLoopThread: @unchecked Sendable {
    private let name: String
    private let ready = DispatchSemaphore(value: 0)
    private var runLoop: CFRunLoop?

    init(name: String) {
        self.name = name
    }

    /// Returns once the runloop exists, so callers can enqueue immediately.
    func start() {
        let thread = Thread { [self] in
            runLoop = CFRunLoopGetCurrent()
            ready.signal()

            // A runloop with no sources exits at once; observers arrive later.
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

    var cfRunLoop: CFRunLoop? { runLoop }
}
