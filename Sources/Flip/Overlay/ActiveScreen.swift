import AppKit
import CoreGraphics

/// Which screen the overlay belongs on.
///
/// `NSScreen.main` is the wrong answer. It resolves to the screen holding the
/// application's own key window, and Flip is an agent that deliberately never has
/// one — so it falls back to the screen carrying the menu bar. On a two monitor
/// desk that is a coin flip against where the user is actually looking.
///
/// The screen holding the frontmost window is the honest answer: it is the window
/// being switched away from, so it is where the eyes already are.
enum ActiveScreen {
    static func current() -> NSScreen {
        frontmostWindowScreen()
            ?? screen(containingCocoaPoint: NSEvent.mouseLocation)
            ?? NSScreen.main
            ?? NSScreen.screens[0]
    }

    /// The listing comes back front to back, so the first ordinary window is the
    /// frontmost one.
    private static func frontmostWindowScreen() -> NSScreen? {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let listing = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]]
        else { return nil }

        for window in listing {
            guard let layer = window[kCGWindowLayer as String] as? Int, layer == 0,
                  let raw = window[kCGWindowBounds as String],
                  let bounds = CGRect(dictionaryRepresentation: raw as! CFDictionary)
            else { continue }

            return screen(containingWindowServerRect: bounds)
        }

        return nil
    }

    /// The two frameworks disagree about which way is up. CGWindowList puts the
    /// origin at the top left of the primary display with y growing downwards;
    /// NSScreen puts it at the bottom left with y growing upwards. The primary
    /// screen's height is the hinge between them, and getting this wrong picks the
    /// wrong monitor rather than failing outright.
    private static func screen(containingWindowServerRect rect: CGRect) -> NSScreen? {
        guard let primary = primaryScreen else { return nil }

        let point = CGPoint(x: rect.midX, y: primary.frame.maxY - rect.midY)

        return screen(containingCocoaPoint: point)
    }

    private static func screen(containingCocoaPoint point: CGPoint) -> NSScreen? {
        NSScreen.screens.first { $0.frame.contains(point) }
    }

    /// Identified by its origin rather than by position in the array: the display
    /// at the Cocoa origin is the one the window server measures everything from.
    private static var primaryScreen: NSScreen? {
        NSScreen.screens.first { $0.frame.origin == .zero } ?? NSScreen.screens.first
    }
}
