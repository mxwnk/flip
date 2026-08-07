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
