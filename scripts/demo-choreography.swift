// The key sequence for the demonstration recording.
//
// Performed rather than typed, because a synthetic keystroke and a real one
// cannot share a keyboard: any actual key press releases the modifier and ends
// the take. Nobody may touch the keyboard while this runs.
//
//   swift scripts/demo-choreography.swift [scene]
//
// Scenes are separate so each can be recorded on its own: switch, jump, arrange.

import CoreGraphics
import Foundation

// MARK: - Timing
//
// Generous on purpose: this is watched, not used. A hold has to outlast the
// overlay's own delay or the grid never draws, which is the thing being shown.

let beat: UInt32 = 700_000
let pause: UInt32 = 1_100_000
let afterHold: UInt32 = 450_000

// MARK: - Keys

let tab: CGKeyCode = 48
let leftArrow: CGKeyCode = 123
let rightArrow: CGKeyCode = 124
let returnKey: CGKeyCode = 36
let cKey: CGKeyCode = 8
let sKey: CGKeyCode = 1

let option: CGEventFlags = [.maskAlternate]
let controlOption: CGEventFlags = [.maskControl, .maskAlternate]
let shiftOption: CGEventFlags = [.maskShift, .maskAlternate]

let source = CGEventSource(stateID: .hidSystemState)

/// Announced as its own event so a keystroke visualiser shows the modifier going
/// down, rather than only seeing it attached to the next key.
func holdModifier(_ flags: CGEventFlags) {
    let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true)
    event?.type = .flagsChanged
    event?.flags = flags
    event?.post(tap: .cghidEventTap)
    usleep(afterHold)
}

func releaseModifiers() {
    let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
    event?.type = .flagsChanged
    event?.flags = []
    event?.post(tap: .cghidEventTap)
    usleep(pause)
}

func tap(_ key: CGKeyCode, _ flags: CGEventFlags, wait: UInt32 = beat) {
    for isDown in [true, false] {
        let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: isDown)
        event?.flags = flags
        event?.post(tap: .cghidEventTap)
    }
    usleep(wait)
}

// MARK: - Scenes

/// Hold the leader, walk the grid, let go. The one everything else builds on.
func switching() {
    holdModifier(option)
    tap(tab, option, wait: 1_000_000)
    tap(tab, option)
    tap(tab, option)
    releaseModifiers()
}

/// One key straight to an application, and the same key again narrowing the grid
/// to it. Needs a binding pointing at a demonstration application.
func jumping() {
    tap(cKey, option, wait: pause)

    holdModifier(option)
    tap(tab, option, wait: 1_000_000)
    tap(cKey, option, wait: 1_000_000)
    releaseModifiers()
}

/// Halves, filling, and across to the other display.
///
/// Lands on Safari first. Window actions apply to whatever was focused last,
/// and after the jump scene that is the calculator — a small fixed window that
/// looks wrong stretched across half a screen.
func arranging() {
    tap(sKey, option, wait: pause)

    tap(leftArrow, controlOption, wait: pause)
    tap(rightArrow, controlOption, wait: pause)
    tap(returnKey, controlOption, wait: pause)
    tap(rightArrow, shiftOption, wait: pause)
    tap(leftArrow, shiftOption, wait: pause)
}

let scenes: [String: () -> Void] = [
    "switch": switching,
    "jump": jumping,
    "arrange": arranging,
]

let requested = CommandLine.arguments.count > 1 ? [CommandLine.arguments[1]] : ["switch", "jump", "arrange"]

// A moment to get the pointer out of the way and stop touching anything.
usleep(1_500_000)

for name in requested {
    guard let scene = scenes[name] else {
        FileHandle.standardError.write(Data("unknown scene: \(name)\n".utf8))
        exit(1)
    }
    print("— \(name)")
    scene()
    usleep(pause)
}
