import CoreGraphics

enum Configuration {
    /// Held down for the whole interaction: it opens the switcher, it keeps the
    /// switcher open while the selection moves, and letting go is what commits.
    static let leader: CGEventFlags = [.maskAlternate]

    /// Cycles the frontmost application's own windows. macOS reserves Cmd-Tab for
    /// the Dock and will not hand it to any hotkey API, which is the reason an
    /// event tap has to exist at all rather than a set of registered hotkeys.
    static let appLeader: CGEventFlags = [.maskCommand]

}
