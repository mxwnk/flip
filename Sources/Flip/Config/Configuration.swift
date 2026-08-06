import CoreGraphics

enum Configuration {
    /// Hammerspoon still owns Alt-Tab, Cmd-Tab and the Alt-<letter> bindings while
    /// the switcher is being built, and two event taps grabbing the same keys would
    /// fight. Until `switcher/` and `apps.lua` are gone, Flip listens one modifier
    /// over, so both can run at once and be compared side by side.
    ///
    /// Flipping this to false is the entire handover.
    static let coexistWithHammerspoon = true

    /// Held down for the whole interaction: it opens the switcher, it keeps the
    /// switcher open while the selection moves, and letting go is what commits.
    static var leader: CGEventFlags {
        coexistWithHammerspoon ? [.maskAlternate, .maskControl] : [.maskAlternate]
    }

    /// Cycles the frontmost application's own windows. macOS reserves Cmd-Tab for
    /// the Dock and will not hand it to any hotkey API, which is the reason an
    /// event tap has to exist at all rather than a set of registered hotkeys.
    static var appLeader: CGEventFlags {
        coexistWithHammerspoon ? [.maskCommand, .maskControl] : [.maskCommand]
    }

    /// Keys that reach an application with no modifier at all. They are swallowed
    /// globally, so whatever the key normally does is gone. Off while coexisting:
    /// a bare key has no spare modifier to be moved out of Hammerspoon's way.
    static var bareKeysEnabled: Bool { !coexistWithHammerspoon }
}
