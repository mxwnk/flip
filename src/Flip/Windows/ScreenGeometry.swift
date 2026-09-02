import AppKit
import CoreGraphics

/// The two coordinate systems macOS uses for windows: accessibility and the
/// window server measure from the top left with y downwards, NSScreen from the
/// bottom left with y upwards. The primary screen's height is the hinge. Getting
/// it wrong moves a window to the wrong place rather than failing.
@MainActor
enum ScreenGeometry {
    /// By origin, not array position: the display at the Cocoa origin is what
    /// everything else is measured from.
    static var primary: NSScreen? {
        NSScreen.screens.first { $0.frame.origin == .zero } ?? NSScreen.screens.first
    }

    static func cocoa(fromTopLeft rect: CGRect) -> CGRect? {
        guard let primary else { return nil }

        return CGRect(
            x: rect.origin.x,
            y: primary.frame.maxY - rect.origin.y - rect.height,
            width: rect.width,
            height: rect.height
        )
    }

    static func topLeft(fromCocoa rect: CGRect) -> CGRect? {
        guard let primary else { return nil }

        return CGRect(
            x: rect.origin.x,
            y: primary.frame.maxY - rect.origin.y - rect.height,
            width: rect.width,
            height: rect.height
        )
    }

    /// Left to right, then top to bottom, which is how the displays are laid out
    /// in System Settings. `NSScreen.screens` is the order the window server
    /// registered them in, so stepping through it moves by display number
    /// instead — and the display to the right is as likely to be behind you.
    nonisolated static func inArrangementOrder<T>(_ items: [T], by frame: (T) -> CGRect) -> [T] {
        items.sorted {
            let (one, other) = (frame($0), frame($1))

            return one.minX == other.minX ? one.minY > other.minY : one.minX < other.minX
        }
    }

    static func screen(containing cocoaRect: CGRect) -> NSScreen? {
        let centre = CGPoint(x: cocoaRect.midX, y: cocoaRect.midY)

        return NSScreen.screens.first { $0.frame.contains(centre) } ?? NSScreen.main
    }
}
