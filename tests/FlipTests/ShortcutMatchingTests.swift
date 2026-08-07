import Carbon.HIToolbox
import CoreGraphics
import XCTest

@testable import Flip

/// The two bugs that reached the user were both fn: F1 and the arrow keys arrive
/// with it set, and an exact modifier comparison never matched. These pin it.
final class FunctionModifierTests: XCTestCase {
    private func event(_ flags: CGEventFlags) -> CGEvent {
        let event = CGEvent(keyboardEventSource: nil, virtualKey: 48, keyDown: true)!
        event.flags = flags
        return event
    }

    func testFunctionIsNotASignificantModifier() {
        XCTAssertFalse(Modifiers.significant.contains(.maskSecondaryFn))
    }

    func testAKeyCarryingFunctionStillLooksUnmodified() {
        XCTAssertFalse(Modifiers.anyHeld(in: event([.maskSecondaryFn])))
        XCTAssertEqual(Modifiers.held(in: event([.maskSecondaryFn])), [])
    }

    /// What the keyboard really sends for ⌃⌥ and an arrow.
    func testFunctionDoesNotDisturbACombination() {
        let held = Modifiers.held(in: event([.maskControl, .maskAlternate, .maskSecondaryFn]))

        XCTAssertEqual(held, [.maskControl, .maskAlternate])
    }
}

final class WindowShortcutTests: XCTestCase {
    func testEveryActionHasExactlyOneShortcut() {
        let covered = Set(WindowArrangement.shortcuts.map(\.arrangement))

        XCTAssertEqual(covered.count, WindowArrangement.allCases.count)
        XCTAssertEqual(WindowArrangement.shortcuts.count, WindowArrangement.allCases.count)
    }

    func testNoTwoShortcutsShareAKey() {
        let combinations = WindowArrangement.shortcuts.map { "\($0.modifiers.rawValue)-\($0.keyCode)" }

        XCTAssertEqual(Set(combinations).count, combinations.count)
    }

    func testEveryShortcutIsFoundByItsOwnKey() {
        for shortcut in WindowArrangement.shortcuts {
            XCTAssertEqual(
                WindowArrangement.matching(keyCode: shortcut.keyCode, modifiers: shortcut.modifiers),
                shortcut.arrangement,
                shortcut.keys
            )
        }
    }

    /// The bug in full: the hardware adds fn, and the lookup has to survive it.
    func testShortcutsMatchEvenWithTheFunctionBitSet() {
        for shortcut in WindowArrangement.shortcuts {
            XCTAssertEqual(
                WindowArrangement.matching(
                    keyCode: shortcut.keyCode,
                    modifiers: shortcut.modifiers.union(.maskSecondaryFn)
                ),
                shortcut.arrangement,
                "\(shortcut.keys) with fn"
            )
        }
    }

    func testAnExtraModifierIsNotAMatch() {
        for shortcut in WindowArrangement.shortcuts {
            let extra = shortcut.modifiers.contains(.maskCommand) ? CGEventFlags.maskControl : .maskCommand

            XCTAssertNil(
                WindowArrangement.matching(
                    keyCode: shortcut.keyCode, modifiers: shortcut.modifiers.union(extra)
                ),
                shortcut.keys
            )
        }
    }

    func testTabIsNeverAWindowShortcut() {
        for modifiers in [CGEventFlags.maskAlternate, .maskCommand, [.maskAlternate, .maskShift]] {
            XCTAssertNil(WindowArrangement.matching(keyCode: CGKeyCode(kVK_Tab), modifiers: modifiers))
        }
    }

    /// Shift is part of the display bindings, and the switcher reads it as
    /// "backwards", so the two must not collide on the same key.
    func testTheDisplayShortcutsUseShiftAndNothingElseDoes() {
        let withShift = WindowArrangement.shortcuts.filter { $0.modifiers.contains(.maskShift) }

        XCTAssertEqual(Set(withShift.map(\.arrangement)), [.previousDisplay, .nextDisplay])
    }
}

final class DisplayMappingTests: XCTestCase {
    private let left = CGRect(x: 63, y: 0, width: 2497, height: 1410)
    private let right = CGRect(x: 2560, y: 0, width: 2560, height: 1440)

    func testAWindowKeepsItsPlaceProportionally() {
        let leftHalf = WindowArranger.frame(for: .leftHalf, in: left)!

        let moved = WindowArranger.mapped(leftHalf, from: left, to: right)

        XCTAssertEqual(moved.minX, right.minX, accuracy: 0.001)
        XCTAssertEqual(moved.width, right.width / 2, accuracy: 0.001)
        XCTAssertEqual(moved.height, right.height, accuracy: 0.001)
    }

    func testARightHalfArrivesAsARightHalf() {
        let rightHalf = WindowArranger.frame(for: .rightHalf, in: left)!

        let moved = WindowArranger.mapped(rightHalf, from: left, to: right)

        XCTAssertEqual(moved.maxX, right.maxX, accuracy: 0.001)
        XCTAssertEqual(moved.width, right.width / 2, accuracy: 0.001)
    }

    func testMovingToTheSameAreaChangesNothing() {
        let window = CGRect(x: 300, y: 200, width: 800, height: 600)

        XCTAssertEqual(WindowArranger.mapped(window, from: left, to: left), window)
    }

    func testTheRoundTripReturnsTheOriginalFrame() {
        let window = CGRect(x: 300, y: 200, width: 800, height: 600)

        let there = WindowArranger.mapped(window, from: left, to: right)
        let back = WindowArranger.mapped(there, from: right, to: left)

        XCTAssertEqual(back.minX, window.minX, accuracy: 0.001)
        XCTAssertEqual(back.minY, window.minY, accuracy: 0.001)
        XCTAssertEqual(back.width, window.width, accuracy: 0.001)
        XCTAssertEqual(back.height, window.height, accuracy: 0.001)
    }

    func testAMovedWindowStaysInsideTheTargetArea() {
        for arrangement in [WindowArrangement.leftHalf, .rightHalf, .topHalf, .bottomHalf, .maximize] {
            let source = WindowArranger.frame(for: arrangement, in: left)!
            let moved = WindowArranger.mapped(source, from: left, to: right)

            XCTAssertTrue(right.insetBy(dx: -0.001, dy: -0.001).contains(moved), "\(arrangement)")
        }
    }
}
