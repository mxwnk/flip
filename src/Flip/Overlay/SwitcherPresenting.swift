import Foundation

/// What the key router drives. The router deals in intent and knows nothing
/// about the overlay being an NSPanel.
@MainActor
protocol SwitcherPresenting: AnyObject {
    /// Opens, or moves the selection if already open. Negative steps go backwards.
    func showAllWindows(step: Int)

    func showWindows(of bundleID: String, step: Int)

    func showFrontmostAppWindows(step: Int)

    /// Brings an application forward without opening the overlay.
    func reachApplication(_ bundleID: String)

    /// Moves or resizes the focused window. Nothing to do with the overlay, but
    /// the router speaks to one collaborator.
    func arrangeWindow(_ arrangement: WindowArrangement)

    func move(by step: Int)
    func moveRow(by step: Int)

    /// Closes and focuses the selection.
    func commit()

    /// Closes and focuses nothing.
    func cancel()

    /// The router tracks visibility itself to decide synchronously, so it has to
    /// hear about closes it did not ask for.
    var onUnexpectedClose: (() -> Void)? { get set }
}
