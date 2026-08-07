import CoreGraphics

/// Where the tiles go. Computed rather than left to a SwiftUI grid: rows follow
/// explicit thresholds and tiles shrink to fit rather than wrap.
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

    /// Stepping `columns` places through the flat list only preserves the column
    /// when the last row is full, so this walks rows and skips gaps.
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
