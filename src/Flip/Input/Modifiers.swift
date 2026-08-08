import CoreGraphics

enum Modifiers {
    /// Caps lock, fn and the device bits are left out: the device bits are often
    /// set with no key held, caps lock must not hold a finished overlay open, and
    /// fn is set by the hardware for the F-row and the arrows alike — so
    /// "Control and Option" would never match a real keypress.
    static let significant: CGEventFlags = [
        .maskCommand, .maskAlternate, .maskControl, .maskShift,
    ]

    static func held(in event: CGEvent) -> CGEventFlags {
        significant(in: event.flags)
    }

    static func significant(in flags: CGEventFlags) -> CGEventFlags {
        flags.intersection(significant)
    }

    static func anyHeld(in event: CGEvent) -> Bool {
        !held(in: event).isEmpty
    }
}
