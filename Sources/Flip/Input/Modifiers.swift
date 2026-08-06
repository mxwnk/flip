import CoreGraphics

enum Modifiers {
    /// Caps lock and the device dependent bits are deliberately left out. The
    /// latter occupy the low bits of the flags and are frequently set with no key
    /// held at all, so any exact comparison including them would never match —
    /// and caps lock must not be able to hold a finished overlay open.
    static let significant: CGEventFlags = [
        .maskCommand, .maskAlternate, .maskControl, .maskShift, .maskSecondaryFn,
    ]

    static func held(in event: CGEvent) -> CGEventFlags {
        event.flags.intersection(significant)
    }

    static func anyHeld(in event: CGEvent) -> Bool {
        !held(in: event).isEmpty
    }
}
