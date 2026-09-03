import SwiftUI

/// A display with the window drawn where the arrangement puts it. Names like
/// "bottom right quarter" all read alike in a list; the picture is what tells
/// two rules apart at a glance.
struct ArrangementPreview: View {
    let arrangement: WindowArrangement
    /// A rule with no application yet is drawn grey, so an unfinished card does
    /// not read as loudly as a finished one.
    var active = true
    var width: CGFloat = 46

    private var height: CGFloat { (width * 0.62).rounded() }

    var body: some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(Color.primary.opacity(0.06))
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.14), lineWidth: 1)
            )
            .overlay(window.padding(2))
            .frame(width: width, height: height)
    }

    @ViewBuilder
    private var window: some View {
        GeometryReader { geometry in
            let area = unitFrame

            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(active ? SettingsTab.layouts.tint.opacity(0.85) : Color.primary.opacity(0.22))
                .frame(
                    width: max(area.width * geometry.size.width - 1, 2),
                    height: max(area.height * geometry.size.height - 1, 2)
                )
                .offset(x: area.minX * geometry.size.width, y: area.minY * geometry.size.height)
        }
    }

    /// The same geometry the arranger uses, flipped: it measures from the bottom
    /// left and SwiftUI from the top left.
    private var unitFrame: CGRect {
        let unit = CGRect(x: 0, y: 0, width: 1, height: 1)
        guard let frame = WindowArranger.frame(for: arrangement, in: unit) else { return unit }

        return CGRect(
            x: frame.minX, y: 1 - frame.maxY, width: frame.width, height: frame.height
        )
    }
}
