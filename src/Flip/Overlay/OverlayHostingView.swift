import AppKit
import SwiftUI

/// Roughly a tile's worth of finger, so a flick browses rather than bolting.
/// Outside the view: a generic type cannot hold a static stored property.
private let pointsPerStep: CGFloat = 30

/// AppKit rather than SwiftUI's `onHover`, whose tracking area is live only
/// while its application is active — and Flip never activates.
final class OverlayHostingView<Content: View>: NSHostingView<Content> {
    /// Origin at the view's top left, matching how `OverlayLayout` counts rows.
    var onPointerMoved: ((CGPoint) -> Void)?
    var onClick: ((CGPoint) -> Void)?
    /// Whole steps: the grid has no scroll position to land between.
    var onScroll: ((Int) -> Void)?

    /// How far a trackpad has been pushed since the last step it produced.
    private var travelled: CGFloat = 0

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

    override func scrollWheel(with event: NSEvent) {
        let step = steps(from: event)
        guard step != 0 else { return }

        onScroll?(step)
    }

    /// A wheel notch is one step; a trackpad has to travel a threshold to earn
    /// one. The sign comes from AppKit with the system's scrolling direction
    /// already applied, so this follows every other list on the machine.
    private func steps(from event: NSEvent) -> Int {
        let vertical = event.scrollingDeltaY
        let horizontal = event.scrollingDeltaX
        let delta = abs(vertical) >= abs(horizontal) ? vertical : horizontal

        // The line count, not the event: an accelerated wheel sends several at
        // once. A fractional line still earns a step, or a notch is lost.
        guard event.hasPreciseScrollingDeltas else {
            let lines = Int(delta.rounded())
            guard lines == 0 else { return -lines }

            return delta > 0 ? -1 : (delta < 0 ? 1 : 0)
        }

        // A new gesture cannot inherit what the last left below the threshold.
        if event.phase == .began { travelled = 0 }
        travelled += delta

        let earned = Int(travelled / pointsPerStep)
        guard earned != 0 else { return 0 }

        travelled -= CGFloat(earned) * pointsPerStep

        return -earned
    }

    private func position(of event: NSEvent) -> CGPoint {
        let local = convert(event.locationInWindow, from: nil)
        return isFlipped ? local : CGPoint(x: local.x, y: bounds.height - local.y)
    }
}
