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

    /// Which tile is under `point`, measured from the top left of the screen the
    /// overlay covers, y downwards. Nil in the gaps and the dimmed area, so
    /// hovering nothing leaves the selection alone.
    func index(at point: CGPoint, in container: CGSize, count: Int) -> Int? {
        let x = point.x - (container.width - panelSize.width) / 2 - Theme.panelPadding
        let y = point.y - (container.height - panelSize.height) / 2 - Theme.panelPadding
        guard x >= 0, y >= 0 else { return nil }

        let row = Int(y / (tileHeight + Theme.tilePadding))
        guard row < rows, y - CGFloat(row) * (tileHeight + Theme.tilePadding) <= tileHeight
        else { return nil }

        // A short last row is centred by the stack that draws it, so its tiles
        // do not line up with those above and need their own column maths.
        let inRow = min(count - row * columns, columns)
        guard inRow > 0 else { return nil }
        let indent = CGFloat(columns - inRow) * (tileWidth + Theme.tilePadding) / 2
        let offset = x - indent
        guard offset >= 0 else { return nil }

        let column = Int(offset / (tileWidth + Theme.tilePadding))
        guard column < inRow, offset - CGFloat(column) * (tileWidth + Theme.tilePadding) <= tileWidth
        else { return nil }

        return row * columns + column
    }

    /// Stepping `columns` through the flat list only keeps the column when the
    /// last row is full, so this works in rows.
    func index(movingRowBy step: Int, from selected: Int, count: Int) -> Int {
        guard count > 0 else { return selected }

        let column = selected % columns
        let row = selected / columns
        let target = (row + step % rows + rows) % rows
        let first = target * columns
        guard first < count else { return selected }

        // A short last row has nothing under the rightmost columns. Landing on
        // its end beats skipping it: the row is visibly there, so a key that does
        // nothing reads as broken.
        let last = min(first + columns, count) - 1

        return min(first + column, last)
    }
}
