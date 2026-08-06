import AppKit
import CoreGraphics

/// Which screen the overlay belongs on. `NSScreen.main` is wrong here: it needs
/// the app's own key window, which an agent never has, and falls back to the
/// menu bar screen. The frontmost window's screen is where the eyes are.
enum ActiveScreen {
    static func current() -> NSScreen {
        frontmostWindowScreen()
            ?? screen(containingCocoaPoint: NSEvent.mouseLocation)
            ?? NSScreen.main
            ?? NSScreen.screens[0]
    }

    /// The listing is front to back, so the first ordinary window is frontmost.
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

    /// CGWindowList measures from the top left with y downwards, NSScreen from the
    /// bottom left with y upwards. Getting this wrong picks the wrong monitor
    /// rather than failing.
    private static func screen(containingWindowServerRect rect: CGRect) -> NSScreen? {
        guard let primary = primaryScreen else { return nil }

        let point = CGPoint(x: rect.midX, y: primary.frame.maxY - rect.midY)

        return screen(containingCocoaPoint: point)
    }

    private static func screen(containingCocoaPoint point: CGPoint) -> NSScreen? {
        NSScreen.screens.first { $0.frame.contains(point) }
    }

    /// Identified by origin, not array position: the display at the Cocoa origin
    /// is what the window server measures from.
    private static var primaryScreen: NSScreen? {
        NSScreen.screens.first { $0.frame.origin == .zero } ?? NSScreen.screens.first
    }
}
