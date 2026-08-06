import Foundation
import OSLog

/// What the key router drives.
///
/// Split out so the key handling can be finished and tested before any pixels
/// exist: step four swaps the logging stub below for the real overlay and the
/// router does not change.
@MainActor
protocol SwitcherPresenting: AnyObject {
    /// Opens the overlay over every window on the current space, or moves the
    /// selection if it is already open. Negative steps go backwards.
    func showAllWindows(step: Int)

    /// The same, restricted to one application's windows.
    func showWindows(of bundleID: String, step: Int)

    /// The same, for whichever application is in front.
    func showFrontmostAppWindows(step: Int)

    func move(by step: Int)
    func moveRow(by step: Int)

    /// Closes the overlay and focuses the selection.
    func commit()

    /// Closes the overlay and focuses nothing.
    func cancel()
}

/// Stands in for the overlay until step four. Every decision the router makes
/// shows up in `make logs`, which is enough to check the key handling on its own.
@MainActor
final class LoggingPresenter: SwitcherPresenting {
    private let log = Logger(subsystem: Bundle.identifier, category: "switcher")

    func showAllWindows(step: Int) {
        log.notice("show all windows, step \(step, privacy: .public)")
    }

    func showWindows(of bundleID: String, step: Int) {
        log.notice("show windows of \(bundleID, privacy: .public), step \(step, privacy: .public)")
    }

    func showFrontmostAppWindows(step: Int) {
        log.notice("show frontmost app windows, step \(step, privacy: .public)")
    }

    func move(by step: Int) {
        log.notice("move \(step, privacy: .public)")
    }

    func moveRow(by step: Int) {
        log.notice("move row \(step, privacy: .public)")
    }

    func commit() {
        log.notice("commit")
    }

    func cancel() {
        log.notice("cancel")
    }
}
