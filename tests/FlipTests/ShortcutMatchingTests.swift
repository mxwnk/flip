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
    /// Every check runs for every combination of the two modifiers the table now
    /// depends on. A rule that only holds for the defaults is not a rule.
    private func forEachChoice(
        _ body: (ModifierChoice, DisplayMoveModifier, [WindowShortcut]) -> Void
    ) {
        for leader in ModifierChoice.allCases {
            for move in DisplayMoveModifier.allCases {
                body(
                    leader, move,
                    WindowArrangement.shortcuts(leader: leader, displayMove: move)
                )
            }
        }
    }

    /// Load-bearing since the halves became settable: the two share the arrows,
    /// and nothing but the shape of the two sets keeps them apart.
    func testNoWindowLeaderCanEverBeADisplayMove() {
        let moves = Set(DisplayMoveModifier.allCases.map(\.flags.rawValue))

        for leader in ModifierChoice.allCases {
            XCTAssertFalse(moves.contains(leader.flags.rawValue), "\(leader)")
        }
    }

    func testEveryActionHasExactlyOneShortcut() {
        forEachChoice { leader, move, shortcuts in
            XCTAssertEqual(Set(shortcuts.map(\.arrangement)).count, WindowArrangement.allCases.count, "\(leader)/\(move)")
            XCTAssertEqual(shortcuts.count, WindowArrangement.allCases.count, "\(leader)/\(move)")
        }
    }

    func testNoTwoShortcutsShareAKey() {
        forEachChoice { leader, move, shortcuts in
            let combinations = shortcuts.map { "\($0.modifiers.rawValue)-\($0.keyCode)" }

            XCTAssertEqual(Set(combinations).count, combinations.count, "\(leader)/\(move)")
        }
    }

    func testEveryShortcutIsFoundByItsOwnKey() {
        forEachChoice { leader, move, shortcuts in
            for shortcut in shortcuts {
                XCTAssertEqual(
                    WindowArrangement.matching(                        keyCode: shortcut.keyCode, modifiers: shortcut.modifiers,
                        leader: leader, displayMove: move
                    ),
                    shortcut.arrangement,
                    shortcut.keys
                )
            }
        }
    }

    /// The bug in full: the hardware adds fn, and the lookup has to survive it.
    func testShortcutsMatchEvenWithTheFunctionBitSet() {
        forEachChoice { leader, move, shortcuts in
            for shortcut in shortcuts {
                XCTAssertEqual(
                    WindowArrangement.matching(                        keyCode: shortcut.keyCode,
                        modifiers: shortcut.modifiers.union(.maskSecondaryFn),
                        leader: leader, displayMove: move
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
        forEachChoice { leader, move, shortcuts in
            for shortcut in shortcuts {
                // Whichever of the four this shortcut does not already carry.
                // CGEventFlags is an option set, not a sequence, so the candidates
                // are listed rather than derived.
                let candidates: [CGEventFlags] = [.maskCommand, .maskControl, .maskShift, .maskAlternate]
                guard let extra = candidates.first(where: { !shortcut.modifiers.contains($0) })
                else { continue }

                XCTAssertNotEqual(
                    WindowArrangement.matching(                        keyCode: shortcut.keyCode,
                        modifiers: shortcut.modifiers.union(extra),
                        leader: leader, displayMove: move
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

        forEachChoice { leader, move, _ in
            for modifiers in held {
                XCTAssertNil(WindowArrangement.matching(                    keyCode: CGKeyCode(kVK_Tab), modifiers: modifiers,
                    leader: leader, displayMove: move
                ), "\(leader)/\(move)")
            }
        }
    }

    /// The display moves take the same arrows as the halves, so whichever modifier
    /// they are given has to differ from the halves' — otherwise one of them is
    /// simply unreachable.
    func testTheDisplayMovesNeverCollideWithTheHalves() {
        let moves: Set<WindowArrangement> = [.previousDisplay, .nextDisplay]

        forEachChoice { leader, move, shortcuts in
            let displays = shortcuts.filter { moves.contains($0.arrangement) }
            let others = shortcuts.filter { !moves.contains($0.arrangement) }

            XCTAssertEqual(displays.count, 2, "\(leader)/\(move)")
            for display in displays {
                let taken = others.contains { other in
                    other.keyCode == display.keyCode && other.modifiers == display.modifiers
                }

                XCTAssertFalse(taken, "\(leader)/\(move): \(display.keys) is taken")
            }
        }
    }

    /// Shift means backwards to the switcher, so a display move carrying it must
    /// not sit on a key the switcher also reads.
    func testTheShiftChoiceStaysOffTheSwitcherKeys() {
        let shortcuts = WindowArrangement.shortcuts(leader: .optionControl, displayMove: .shiftOption)

        for shortcut in shortcuts where shortcut.modifiers.contains(.maskShift) {
            XCTAssertNotEqual(shortcut.keyCode, CGKeyCode(kVK_Tab), shortcut.keys)
        }
    }

    func testTheThreeModifierChoiceUsesAllThree() {
        let shortcuts = WindowArrangement.shortcuts(leader: .optionControl, displayMove: .allThree)
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
/// The keys are a setting now, so the table has to follow the file rather than
/// the constants it was written with.
final class ArrangeKeyTests: XCTestCase {
    func testAKeyFromTheConfigurationMovesTheShortcut() {
        var keys = WindowArrangement.defaultKeys
        keys[.maximize] = "m"

        let shortcuts = WindowArrangement.shortcuts(
            leader: .optionControl, displayMove: .shiftOption, keys: keys
        )
        let maximize = shortcuts.first { $0.arrangement == .maximize }

        XCTAssertEqual(maximize?.keyCode, KeyboardLayout.keyCode(forBinding: "m"))
        XCTAssertEqual(maximize?.keys, "⌃⌥M")
    }

    func testTheKeyItLeavesBehindStopsMatching() {
        var keys = WindowArrangement.defaultKeys
        keys[.maximize] = "m"

        XCTAssertNil(WindowArrangement.matching(
            keyCode: CGKeyCode(kVK_Return), modifiers: ModifierChoice.optionControl.flags,
            leader: .optionControl, displayMove: .shiftOption, keys: keys
        ))
    }

    /// A key the current layout cannot produce drops its row instead of taking
    /// the whole table down with it.
    func testAKeyNoKeyboardProducesIsLeftOut() {
        var keys = WindowArrangement.defaultKeys
        keys[.maximize] = "nonsense"

        let shortcuts = WindowArrangement.shortcuts(
            leader: .optionControl, displayMove: .shiftOption, keys: keys
        )

        XCTAssertEqual(shortcuts.count, WindowArrangement.allCases.count - 1)
        XCTAssertFalse(shortcuts.contains { $0.arrangement == .maximize })
    }
}
