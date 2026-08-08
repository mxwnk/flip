import AppKit
import SwiftUI

/// Roughly a tile's worth of finger. Short enough to feel direct, long enough
/// that an ordinary flick does not race through everything open. Outside the
/// view because a generic type cannot hold a static stored property.
private let pointsPerStep: CGFloat = 30

/// Mouse handling in AppKit rather than SwiftUI's `onHover`, whose tracking area
/// is only live while its own application is active — and Flip never activates.
/// `.activeAlways` is the point.
final class OverlayHostingView<Content: View>: NSHostingView<Content> {
    /// Origin at the view's top left, matching how `OverlayLayout` counts rows.
    var onPointerMoved: ((CGPoint) -> Void)?
    var onClick: ((CGPoint) -> Void)?
    /// Whole steps through the list, never a distance: the grid has no scroll
    /// position to land between.
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

    /// A wheel notch is one step. A trackpad reports a continuous distance
    /// instead, so it takes a threshold's worth to earn one.
    ///
    /// The sign is taken as AppKit gives it, which already has the system's
    /// scrolling direction applied — so this follows whatever every other list
    /// on the machine does rather than deciding for itself. Positive means the
    /// content would move down, which is a step back through the list.
    private func steps(from event: NSEvent) -> Int {
        let vertical = event.scrollingDeltaY
        let horizontal = event.scrollingDeltaX
        let delta = abs(vertical) >= abs(horizontal) ? vertical : horizontal

        // A wheel reports whole lines, and an accelerated one reports several at
        // once — so this follows the count rather than the event. Measured: two
        // lines used to step one tile, which reads as a stuck wheel. A driver
        // sending a fraction of a line still gets its step, or a notch is lost.
        guard event.hasPreciseScrollingDeltas else {
            let lines = Int(delta.rounded())
            guard lines == 0 else { return -lines }

            return delta > 0 ? -1 : (delta < 0 ? 1 : 0)
        }

        // A new gesture starts from nothing, so a flick cannot inherit what the
        // last one left below the threshold.
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
