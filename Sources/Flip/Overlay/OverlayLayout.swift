import CoreGraphics

/// Where the tiles go. Computed rather than left to a SwiftUI grid, because the
/// row count follows explicit thresholds and the tiles have to shrink to fit
/// rather than wrap.
struct OverlayLayout {
    let rows: Int
    let columns: Int
    let tileWidth: CGFloat
    let tileHeight: CGFloat
    let thumbnailHeight: CGFloat
    let panelSize: CGSize

    init(count: Int, screen: CGSize) {
        let count = max(count, 1)

        var rows = 1
        for threshold in Theme.rowThresholds where count > threshold {
            rows += 1
        }
        let columns = Int((Double(count) / Double(rows)).rounded(.up))

        let usable = screen.width * Theme.panelWidthFraction
            - Theme.panelPadding * 2
            - Theme.tilePadding * CGFloat(columns - 1)
        let tileWidth = min(Theme.tileWidth, usable / CGFloat(columns))
        let thumbnailHeight = (tileWidth * Theme.thumbnailRatio).rounded(.down)

        self.rows = rows
        self.columns = columns
        self.tileWidth = tileWidth
        self.thumbnailHeight = thumbnailHeight
        self.tileHeight = thumbnailHeight + Theme.titleHeight
        self.panelSize = CGSize(
            width: CGFloat(columns) * tileWidth
                + Theme.tilePadding * CGFloat(columns - 1)
                + Theme.panelPadding * 2,
            height: CGFloat(rows) * (thumbnailHeight + Theme.titleHeight)
                + Theme.tilePadding * CGFloat(rows - 1)
                + Theme.panelPadding * 2
        )
    }

    /// Moves within the column instead of stepping `columns` places through the
    /// flat list, which only preserves the column when the last row happens to
    /// be full. The last row can be short, so keep going rather than landing on
    /// a gap.
    func index(movingRowBy step: Int, from selected: Int, count: Int) -> Int {
        let column = selected % columns
        var row = selected / columns

        for _ in 0..<rows {
            row = (row + step % rows + rows) % rows
            let candidate = row * columns + column
            if candidate < count { return candidate }
        }

        return selected
    }
}
