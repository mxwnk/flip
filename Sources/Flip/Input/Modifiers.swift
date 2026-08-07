import CoreGraphics

enum Modifiers {
    /// Caps lock, fn, and the device dependent bits are deliberately left out.
    ///
    /// The device bits are frequently set with no key held at all. Caps lock must
    /// not be able to hold a finished overlay open. And fn is set by the hardware
    /// for whole groups of keys — the F-row and the arrows both carry it — so a
    /// binding written as "Control and Option" would never match a real keypress.
    static let significant: CGEventFlags = [
        .maskCommand, .maskAlternate, .maskControl, .maskShift,
    ]

    static func held(in event: CGEvent) -> CGEventFlags {
        event.flags.intersection(significant)
    }

    static func anyHeld(in event: CGEvent) -> Bool {
        !held(in: event).isEmpty
    }
}
