import CoreGraphics
import XCTest

@testable import Flip

private let screen = CGSize(width: 2560, height: 1440)

final class GridShapeTests: XCTestCase {
    func testRowsFollowTheThresholds() {
        for (count, expected) in [(1, 1), (5, 1), (6, 2), (12, 2), (13, 3), (20, 3)] {
            XCTAssertEqual(
                OverlayLayout(count: count, screen: screen).rows, expected,
                "\(count) windows"
            )
        }
    }

    func testColumnsDivideWindowsAcrossRows() {
        for (count, expected) in [(5, 5), (6, 3), (13, 5), (15, 5)] {
            XCTAssertEqual(
                OverlayLayout(count: count, screen: screen).columns, expected,
                "\(count) windows"
            )
        }
    }

    func testEmptyListStillProducesAUsableLayout() {
        let layout = OverlayLayout(count: 0, screen: screen)

        XCTAssertEqual(layout.rows, 1)
        XCTAssertGreaterThanOrEqual(layout.columns, 1)
    }

    func testTilesShrinkRatherThanOverflowANarrowScreen() {
        let narrow = OverlayLayout(count: 15, screen: CGSize(width: 1280, height: 800))

        XCTAssertLessThanOrEqual(narrow.panelSize.width, 1280)
        XCTAssertLessThanOrEqual(narrow.tileWidth, Theme.tileWidth)
    }
}

final class RowMovementTests: XCTestCase {
    /// Fifteen windows are three full rows of five.
    private let full = OverlayLayout(count: 15, screen: screen)

    /// Thirteen leaves the last row two short, which is the case that plain
    /// "step forward by one row" arithmetic gets wrong.
    private let ragged = OverlayLayout(count: 13, screen: screen)

    func testDownStaysInTheSameColumn() {
        XCTAssertEqual(full.index(movingRowBy: 1, from: 2, count: 15), 7)
        XCTAssertEqual(full.index(movingRowBy: 1, from: 7, count: 15), 12)
    }

    func testUpStaysInTheSameColumn() {
        XCTAssertEqual(full.index(movingRowBy: -1, from: 12, count: 15), 7)
        XCTAssertEqual(full.index(movingRowBy: -1, from: 7, count: 15), 2)
    }

    func testMovingOffTheBottomWrapsToTheTop() {
        XCTAssertEqual(full.index(movingRowBy: 1, from: 12, count: 15), 2)
    }

    func testMovingOffTheTopWrapsToTheBottom() {
        XCTAssertEqual(full.index(movingRowBy: -1, from: 2, count: 15), 12)
    }

    /// Thirteen windows fill rows of 5, 5 and 3, so columns 3 and 4 have no tile
    /// in the last row.
    func testAGapInTheShortLastRowIsSkipped() {
        XCTAssertEqual(ragged.index(movingRowBy: 1, from: 9, count: 13), 4)
    }

    func testAColumnThatReachesTheShortRowUsesIt() {
        XCTAssertEqual(ragged.index(movingRowBy: 1, from: 7, count: 13), 12)
    }

    func testASingleRowHasNowhereToGo() {
        let single = OverlayLayout(count: 4, screen: screen)

        XCTAssertEqual(single.index(movingRowBy: 1, from: 2, count: 4), 2)
        XCTAssertEqual(single.index(movingRowBy: -1, from: 2, count: 4), 2)
    }
}

final class HitTestTests: XCTestCase {
    /// The centre of tile `index`, derived the same way the stacks that draw it
    /// are: rows from the top, and a short last row centred rather than ragged.
    private func centre(of index: Int, in layout: OverlayLayout, count: Int) -> CGPoint {
        let row = index / layout.columns
        let column = index % layout.columns
        let inRow = min(count - row * layout.columns, layout.columns)
        let indent = CGFloat(layout.columns - inRow) * (layout.tileWidth + Theme.tilePadding) / 2

        return CGPoint(
            x: (screen.width - layout.panelSize.width) / 2 + Theme.panelPadding + indent
                + CGFloat(column) * (layout.tileWidth + Theme.tilePadding) + layout.tileWidth / 2,
            y: (screen.height - layout.panelSize.height) / 2 + Theme.panelPadding
                + CGFloat(row) * (layout.tileHeight + Theme.tilePadding) + layout.tileHeight / 2
        )
    }

    func testEveryTileFindsItself() {
        for count in [1, 4, 5, 6, 7, 12, 13, 17] {
            let layout = OverlayLayout(count: count, screen: screen)
            for index in 0..<count {
                XCTAssertEqual(
                    layout.index(at: centre(of: index, in: layout, count: count), in: screen, count: count),
                    index,
                    "tile \(index) of \(count)"
                )
            }
        }
    }

    /// The reason the dimmed backdrop is not simply treated as the nearest tile.
    func testTheBackdropIsNotATile() {
        let layout = OverlayLayout(count: 6, screen: screen)
        for point in [
            CGPoint(x: 0, y: 0),
            CGPoint(x: screen.width - 1, y: screen.height - 1),
            CGPoint(x: screen.width / 2, y: 4),
        ] {
            XCTAssertNil(layout.index(at: point, in: screen, count: 6), "\(point)")
        }
    }

    func testGapsBetweenTilesSelectNothing() {
        let layout = OverlayLayout(count: 6, screen: screen)
        let first = centre(of: 0, in: layout, count: 6)

        // Straight down from the first tile, into the space between the rows.
        let betweenRows = CGPoint(x: first.x, y: first.y + layout.tileHeight / 2 + Theme.tilePadding / 2)
        XCTAssertNil(layout.index(at: betweenRows, in: screen, count: 6))

        // And sideways, into the space between two columns.
        let betweenColumns = CGPoint(x: first.x + layout.tileWidth / 2 + Theme.tilePadding / 2, y: first.y)
        XCTAssertNil(layout.index(at: betweenColumns, in: screen, count: 6))
    }

    /// Seven windows make two rows of four with the last row one short, so the
    /// bottom tiles sit half a step right of the ones above them.
    func testAShortLastRowIsCentred() {
        let layout = OverlayLayout(count: 7, screen: screen)
        XCTAssertEqual(layout.columns, 4)

        let above = centre(of: 0, in: layout, count: 7)
        let below = centre(of: 4, in: layout, count: 7)
        XCTAssertEqual(below.x - above.x, (layout.tileWidth + Theme.tilePadding) / 2, accuracy: 0.001)

        // Directly under the first tile is the indent, not the fifth tile.
        XCTAssertNil(layout.index(at: CGPoint(x: above.x - layout.tileWidth / 2 + 1, y: below.y), in: screen, count: 7))
    }

    /// Past the last window the row still exists, but those places are empty.
    func testEmptyPlacesInTheLastRowSelectNothing() {
        let layout = OverlayLayout(count: 6, screen: screen)
        let lastRow = centre(of: 3, in: layout, count: 6).y

        XCTAssertNil(layout.index(at: CGPoint(x: screen.width - 1, y: lastRow), in: screen, count: 6))
    }
}
