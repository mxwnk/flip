import Carbon.HIToolbox
import CoreGraphics
import XCTest

@testable import Flip

final class WindowArrangementTests: XCTestCase {
    /// A real visible frame — menu bar off the top, Dock down the left — so the
    /// origin is not zero and an off-by-origin mistake shows up.
    private let area = CGRect(x: 63, y: 0, width: 2497, height: 1410)

    private func frame(_ arrangement: WindowArrangement) -> CGRect? {
        WindowArranger.frame(for: arrangement, in: area)
    }

    func testMaximiseIsTheVisibleFrameAndNotTheWholeScreen() {
        XCTAssertEqual(frame(.maximize), area)
    }

    func testTheHalvesTogetherCoverTheAreaExactly() {
        let left = frame(.leftHalf)!
        let right = frame(.rightHalf)!

        XCTAssertEqual(left.minX, area.minX)
        XCTAssertEqual(left.maxX, right.minX, accuracy: 0.001)
        XCTAssertEqual(right.maxX, area.maxX, accuracy: 0.001)
        XCTAssertEqual(left.width, right.width, accuracy: 0.001)
    }

    func testTheHalvesUseTheFullHeight() {
        for half in [WindowArrangement.leftHalf, .rightHalf] {
            XCTAssertEqual(frame(half)!.height, area.height, "\(half)")
        }
    }

    /// Cocoa counts upwards, so the top half is the one with the larger y.
    func testTopIsAboveBottom() {
        let top = frame(.topHalf)!
        let bottom = frame(.bottomHalf)!

        XCTAssertGreaterThan(top.minY, bottom.minY)
        XCTAssertEqual(bottom.maxY, top.minY, accuracy: 0.001)
        XCTAssertEqual(top.maxY, area.maxY, accuracy: 0.001)
    }

    func testTheHorizontalHalvesUseTheFullWidth() {
        for half in [WindowArrangement.topHalf, .bottomHalf] {
            XCTAssertEqual(frame(half)!.width, area.width, "\(half)")
            XCTAssertEqual(frame(half)!.minX, area.minX, "\(half)")
        }
    }

    func testEveryHalfStaysInsideTheArea() {
        for half in [WindowArrangement.leftHalf, .rightHalf, .topHalf, .bottomHalf] {
            XCTAssertTrue(area.contains(frame(half)!), "\(half) escaped the visible frame")
        }
    }

    /// Moving between displays needs screens, so the pure form declines it rather
    /// than inventing an answer.
    func testDisplayMovesAreNotPureGeometry() {
        XCTAssertNil(frame(.nextDisplay))
        XCTAssertNil(frame(.previousDisplay))
    }
}

final class QuarterTests: XCTestCase {
    private let area = CGRect(x: 63, y: 0, width: 2497, height: 1410)

    private var quarters: [WindowArrangement] {
        [.topLeftQuarter, .topRightQuarter, .bottomLeftQuarter, .bottomRightQuarter]
    }

    private func frame(_ arrangement: WindowArrangement) -> CGRect {
        WindowArranger.frame(for: arrangement, in: area)!
    }

    func testEachQuarterIsAQuarterOfTheArea() {
        for quarter in quarters {
            XCTAssertEqual(frame(quarter).width, area.width / 2, accuracy: 0.001, "\(quarter)")
            XCTAssertEqual(frame(quarter).height, area.height / 2, accuracy: 0.001, "\(quarter)")
        }
    }

    /// Four quarters have to cover the area exactly: no gap down the middle, and
    /// no overlap either.
    func testTheFourQuartersTileTheArea() {
        let total = quarters.map { frame($0).width * frame($0).height }.reduce(0, +)
        XCTAssertEqual(total, area.width * area.height, accuracy: 1)

        let union = quarters.map(frame).reduce(frame(.topLeftQuarter)) { $0.union($1) }
        XCTAssertEqual(union, area)
    }

    /// Cocoa counts upwards, so a corner named "top" must have the larger y.
    func testTopCornersSitAboveBottomCorners() {
        XCTAssertGreaterThan(frame(.topLeftQuarter).minY, frame(.bottomLeftQuarter).minY)
        XCTAssertGreaterThan(frame(.topRightQuarter).minY, frame(.bottomRightQuarter).minY)
    }

    func testLeftCornersSitBeforeRightCorners() {
        XCTAssertLessThan(frame(.topLeftQuarter).minX, frame(.topRightQuarter).minX)
        XCTAssertLessThan(frame(.bottomLeftQuarter).minX, frame(.bottomRightQuarter).minX)
    }

    func testTheCornersMeetInTheMiddle() {
        XCTAssertEqual(frame(.topLeftQuarter).maxX, frame(.topRightQuarter).minX, accuracy: 0.001)
        XCTAssertEqual(frame(.bottomLeftQuarter).maxY, frame(.topLeftQuarter).minY, accuracy: 0.001)
    }

    func testEveryQuarterStaysInsideTheArea() {
        for quarter in quarters {
            XCTAssertTrue(area.contains(frame(quarter)), "\(quarter) escaped the visible frame")
        }
    }

    /// The keys must form a square, which is why they are not the vim four.
    /// Pinned by key code, since the character depends on the layout.
    func testTheCornerKeysFormASquare() {
        let table = WindowArrangement.shortcuts(displayMove: .shiftOption)
        let keys = Dictionary(uniqueKeysWithValues: table.map {
            ($0.arrangement, $0.keyCode)
        })

        XCTAssertEqual(keys[.topLeftQuarter], CGKeyCode(kVK_ANSI_U))
        XCTAssertEqual(keys[.topRightQuarter], CGKeyCode(kVK_ANSI_I))
        XCTAssertEqual(keys[.bottomLeftQuarter], CGKeyCode(kVK_ANSI_J))
        XCTAssertEqual(keys[.bottomRightQuarter], CGKeyCode(kVK_ANSI_K))
    }
}

/// `⌃⌥↩` on a window that already fills puts it back where it was.
final class FillToggleTests: XCTestCase {
    private let area = CGRect(x: 0, y: 0, width: 1600, height: 1000)

    private func outcome(
        _ arrangement: WindowArrangement, _ window: CGRect, remembered: CGRect? = nil
    ) -> WindowArranger.Outcome {
        WindowArranger.outcome(for: arrangement, window: window, in: area, remembered: remembered)
    }

    func testFillingRemembersWhereTheWindowWas() {
        let before = CGRect(x: 120, y: 90, width: 700, height: 480)
        let result = outcome(.maximize, before)

        XCTAssertEqual(result.target, area)
        XCTAssertEqual(result.restore, before)
    }

    func testFillingAgainPutsItBackAndForgets() {
        let before = CGRect(x: 120, y: 90, width: 700, height: 480)
        let result = outcome(.maximize, area, remembered: before)

        XCTAssertEqual(result.target, before)
        XCTAssertNil(result.restore, "a restored window has nothing left to go back to")
    }

    func testTheToggleSurvivesAWindowThatCannotHitTheEdgesExactly() {
        // A terminal resizes in whole character cells and stops a few points short.
        let snapped = CGRect(x: 4, y: 7, width: 1591, height: 994)
        let before = CGRect(x: 120, y: 90, width: 700, height: 480)

        XCTAssertEqual(outcome(.maximize, snapped, remembered: before).target, before)
    }

    func testAWindowMerelyCloseToFullStillFills() {
        let large = CGRect(x: 60, y: 40, width: 1480, height: 920)
        let before = CGRect(x: 120, y: 90, width: 700, height: 480)

        XCTAssertEqual(outcome(.maximize, large, remembered: before).target, area)
    }

    /// After a restart, or a window that opened filled, there is nothing to go
    /// back to — and refusing to move looks like the bug this fixes.
    func testWithNothingRememberedItFallsBackToSomethingCentred() {
        let result = outcome(.maximize, area)
        let target = try? XCTUnwrap(result.target)

        XCTAssertEqual(target?.width, area.width * 0.6)
        XCTAssertEqual(target?.height, area.height * 0.6)
        XCTAssertEqual(target?.midX, area.midX)
        XCTAssertEqual(target?.midY, area.midY)
        XCTAssertNil(result.restore)
    }

    func testEveryOtherArrangementIsOneWayAndForgets() {
        for arrangement in WindowArrangement.allCases
        where arrangement != .maximize && arrangement != .nextDisplay && arrangement != .previousDisplay {
            let before = CGRect(x: 120, y: 90, width: 700, height: 480)
            let result = outcome(arrangement, area, remembered: before)

            XCTAssertEqual(
                result.target, WindowArranger.frame(for: arrangement, in: area), "\(arrangement)"
            )
            XCTAssertNil(result.restore, "\(arrangement)")
        }
    }
}
