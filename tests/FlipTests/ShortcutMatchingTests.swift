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
    /// Every check here runs for both settings, because the table now depends on
    /// one and a rule that only holds for the default is not a rule.
    private func forEachChoice(
        _ body: (DisplayMoveModifier, [WindowShortcut]) -> Void
    ) {
        for choice in DisplayMoveModifier.allCases {
            body(choice, WindowArrangement.shortcuts(displayMove: choice))
        }
    }

    func testEveryActionHasExactlyOneShortcut() {
        forEachChoice { choice, shortcuts in
            XCTAssertEqual(Set(shortcuts.map(\.arrangement)).count, WindowArrangement.allCases.count, "\(choice)")
            XCTAssertEqual(shortcuts.count, WindowArrangement.allCases.count, "\(choice)")
        }
    }

    func testNoTwoShortcutsShareAKey() {
        forEachChoice { choice, shortcuts in
            let combinations = shortcuts.map { "\($0.modifiers.rawValue)-\($0.keyCode)" }

            XCTAssertEqual(Set(combinations).count, combinations.count, "\(choice)")
        }
    }

    func testEveryShortcutIsFoundByItsOwnKey() {
        forEachChoice { choice, shortcuts in
            for shortcut in shortcuts {
                XCTAssertEqual(
                    WindowArrangement.matching(
                        keyCode: shortcut.keyCode, modifiers: shortcut.modifiers, displayMove: choice
                    ),
                    shortcut.arrangement,
                    shortcut.keys
                )
            }
        }
    }

    /// The bug in full: the hardware adds fn, and the lookup has to survive it.
    func testShortcutsMatchEvenWithTheFunctionBitSet() {
        forEachChoice { choice, shortcuts in
            for shortcut in shortcuts {
                XCTAssertEqual(
                    WindowArrangement.matching(
                        keyCode: shortcut.keyCode,
                        modifiers: shortcut.modifiers.union(.maskSecondaryFn),
                        displayMove: choice
                    ),
                    shortcut.arrangement,
                    "\(shortcut.keys) with fn"
                )
            }
        }
    }

    /// Holding one modifier too many must not still perform the action. It may
    /// well perform a different one — with the three modifier choice, ⌃⌥⌘← is the
    /// display move sitting one key away from ⌃⌥← for the left half — so the rule
    /// is about this arrangement, not about matching nothing at all.
    func testAnExtraModifierIsNotAMatch() {
        forEachChoice { choice, shortcuts in
            for shortcut in shortcuts {
                // Whichever of the four this shortcut does not already carry.
                // CGEventFlags is an option set, not a sequence, so the candidates
                // are listed rather than derived.
                let candidates: [CGEventFlags] = [.maskCommand, .maskControl, .maskShift, .maskAlternate]
                guard let extra = candidates.first(where: { !shortcut.modifiers.contains($0) })
                else { continue }

                XCTAssertNotEqual(
                    WindowArrangement.matching(
                        keyCode: shortcut.keyCode,
                        modifiers: shortcut.modifiers.union(extra),
                        displayMove: choice
                    ),
                    shortcut.arrangement,
                    shortcut.keys
                )
            }
        }
    }

    func testTabIsNeverAWindowShortcut() {
        let held: [CGEventFlags] = [
            .maskAlternate, .maskCommand,
            [.maskAlternate, .maskShift],
            [.maskControl, .maskAlternate, .maskCommand],
        ]

        for choice in DisplayMoveModifier.allCases {
            for modifiers in held {
                XCTAssertNil(WindowArrangement.matching(
                    keyCode: CGKeyCode(kVK_Tab), modifiers: modifiers, displayMove: choice
                ))
            }
        }
    }

    /// The display moves take the same arrows as the halves, so whichever modifier
    /// they are given has to differ from the halves' — otherwise one of them is
    /// simply unreachable.
    func testTheDisplayMovesNeverCollideWithTheHalves() {
        let moves: Set<WindowArrangement> = [.previousDisplay, .nextDisplay]

        forEachChoice { choice, shortcuts in
            let displays = shortcuts.filter { moves.contains($0.arrangement) }
            let others = shortcuts.filter { !moves.contains($0.arrangement) }

            XCTAssertEqual(displays.count, 2, "\(choice)")
            for display in displays {
                let taken = others.contains { other in
                    other.keyCode == display.keyCode && other.modifiers == display.modifiers
                }

                XCTAssertFalse(taken, "\(choice): \(display.keys) is taken")
            }
        }
    }

    /// Shift means backwards to the switcher, so a display move carrying it must
    /// not sit on a key the switcher also reads.
    func testTheShiftChoiceStaysOffTheSwitcherKeys() {
        let shortcuts = WindowArrangement.shortcuts(displayMove: .shiftOption)

        for shortcut in shortcuts where shortcut.modifiers.contains(.maskShift) {
            XCTAssertNotEqual(shortcut.keyCode, CGKeyCode(kVK_Tab), shortcut.keys)
        }
    }

    func testTheThreeModifierChoiceUsesAllThree() {
        let shortcuts = WindowArrangement.shortcuts(displayMove: .allThree)
        let displays = shortcuts.filter { $0.keys.contains("⌃⌥⌘") }

        XCTAssertEqual(Set(displays.map(\.arrangement)), [.previousDisplay, .nextDisplay])
        for display in displays {
            XCTAssertEqual(display.modifiers, [.maskControl, .maskAlternate, .maskCommand])
        }
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
