import AppKit
import SwiftUI

/// Mouse handling in AppKit rather than SwiftUI's `onHover`, whose tracking area
/// is only live while its own application is active — and Flip never activates.
/// `.activeAlways` is the point.
final class OverlayHostingView<Content: View>: NSHostingView<Content> {
    /// Origin at the view's top left, matching how `OverlayLayout` counts rows.
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
