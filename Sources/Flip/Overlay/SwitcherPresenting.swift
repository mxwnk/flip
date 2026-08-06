import Foundation
import OSLog

/// What the key router drives.
///
/// Split out so the key handling could be finished and tested before any pixels
/// existed: step four swaps the logging stub below for the real overlay and the
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

/// Stands in for the overlay until step four. It resolves the real window list,
/// so what shows up in `make logs` is exactly what will be drawn — including how
/// long it took to assemble.
@MainActor
final class LoggingPresenter: SwitcherPresenting {
    private let log = Logger(subsystem: Bundle.identifier, category: "switcher")
    private let store: WindowStore
    private let frontmost: FrontmostApp

    private var windows: [WindowInfo] = []
    private var selected = 0

    init(store: WindowStore, frontmost: FrontmostApp) {
        self.store = store
        self.frontmost = frontmost
    }

    func showAllWindows(step: Int) {
        open(step: step, label: "all windows") {
            store.currentSpaceWindows()
        }
    }

    func showWindows(of bundleID: String, step: Int) {
        open(step: step, label: bundleID) {
            store.currentSpaceWindows(ofBundleID: bundleID, includingMinimized: true)
        }
    }

    func showFrontmostAppWindows(step: Int) {
        guard let bundleID = frontmost.bundleID else { return }

        showWindows(of: bundleID, step: step)
    }

    func move(by step: Int) {
        guard !windows.isEmpty else { return }

        selected = (selected + step % windows.count + windows.count) % windows.count
        log.notice("selected \(self.describeSelection(), privacy: .public)")
    }

    func moveRow(by step: Int) {
        move(by: step)
    }

    func commit() {
        guard windows.indices.contains(selected) else { return }

        log.notice("commit \(self.describeSelection(), privacy: .public)")
        windows = []
    }

    func cancel() {
        log.notice("cancel")
        windows = []
    }

    /// Reopening replaces the list; stepping keeps it. That is what the overlay
    /// will do too, so the timing measured here is the timing that matters.
    private func open(step: Int, label: String, source: () -> [WindowInfo]) {
        if windows.isEmpty {
            let started = DispatchTime.now().uptimeNanoseconds
            windows = source()
            let elapsed = Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000

            selected = 0
            log.notice("""
            open \(label, privacy: .public): \(self.windows.count, privacy: .public) windows \
            in \(String(format: "%.2f", elapsed), privacy: .public)ms
            """)

            for window in windows {
                log.debug("  \(window.applicationName, privacy: .public) — \(window.title, privacy: .public)\(window.isMinimized ? " [minimised]" : "", privacy: .public)")
            }
        }

        move(by: step)
    }

    private func describeSelection() -> String {
        guard windows.indices.contains(selected) else { return "nothing" }

        let window = windows[selected]

        return "[\(selected + 1)/\(windows.count)] \(window.applicationName) — \(window.title)"
    }
}
