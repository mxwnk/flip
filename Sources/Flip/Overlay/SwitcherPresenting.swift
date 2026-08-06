import Foundation

/// What the key router drives.
///
/// Split out so the key handling could be written and tested before any pixels
/// existed. It stays because it is the seam: the router deals in intent, and
/// nothing about it knows that the overlay is an NSPanel.
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

    /// Set by the wiring. The router tracks visibility itself so it can decide
    /// synchronously whether to swallow a key, which only holds as long as it is
    /// told about closes it did not ask for.
    var onUnexpectedClose: (() -> Void)? { get set }
}
