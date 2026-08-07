import CoreGraphics
import XCTest

@testable import Flip

final class WindowArrangementTests: XCTestCase {
    /// A real visible frame: menu bar off the top, Dock down the left side, so the
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
