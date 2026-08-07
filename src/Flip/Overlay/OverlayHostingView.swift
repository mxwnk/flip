import AppKit
import SwiftUI

/// The overlay's mouse handling, done in AppKit rather than with SwiftUI's
/// `onHover`: that installs a tracking area which is only live while its own
/// application is active, and Flip deliberately never activates. `.activeAlways`
/// is the whole point of doing it here.
final class OverlayHostingView<Content: View>: NSHostingView<Content> {
    /// Both report a point with the origin at the view's top left, matching the
    /// way `OverlayLayout` counts rows.
    var onPointerMoved: ((CGPoint) -> Void)?
    var onClick: ((CGPoint) -> Void)?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .activeAlways, .inVisibleRect],
            owner: self
        ))
    }

    override func mouseMoved(with event: NSEvent) {
        onPointerMoved?(position(of: event))
    }

    override func mouseUp(with event: NSEvent) {
        onClick?(position(of: event))
    }

    private func position(of event: NSEvent) -> CGPoint {
        let local = convert(event.locationInWindow, from: nil)
        return isFlipped ? local : CGPoint(x: local.x, y: bounds.height - local.y)
    }
}
