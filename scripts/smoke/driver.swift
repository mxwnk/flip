// Drives the keyboard, the mouse and the window server for the smoke test.
//
//   driver hold option key tab wait 600 key tab release
//   driver window Flip 500        → id x y w h  of that owner's largest window
//   driver frontmost              → the active application's name
//
// Compiled once rather than run through `swift -e` per step. That matters: the
// compile takes about a second, and a step that arrives a second late lands after
// the modifier was released, which reads as a failure that is not one.
//
// A whole interaction goes in one invocation so its timing is not at the mercy of
// process startup. Nobody may touch the keyboard while it runs — a real keypress
// releases the modifier and ends the sequence halfway through.

import AppKit
import CoreGraphics

let source = CGEventSource(stateID: .hidSystemState)

let keys: [String: CGKeyCode] = [
    "tab": 48, "escape": 53, "return": 36, "space": 49,
    "left": 123, "right": 124, "down": 125, "up": 126,
    "a": 0, "s": 1, "c": 8, "f1": 122,
]

let modifiers: [String: CGEventFlags] = [
    "command": .maskCommand, "option": .maskAlternate,
    "control": .maskControl, "shift": .maskShift,
]

func flags(_ names: String) -> CGEventFlags {
    var result: CGEventFlags = []
    for name in names.split(separator: "+") {
        guard let flag = modifiers[String(name)] else {
            FileHandle.standardError.write(Data("unknown modifier: \(name)\n".utf8))
            exit(2)
        }
        result.insert(flag)
    }
    return result
}

/// Held across the rest of the invocation, so `key` does not have to repeat it.
var held: CGEventFlags = []

func postFlags(_ value: CGEventFlags) {
    held = value
    let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true)
    event?.type = .flagsChanged
    event?.flags = value
    event?.post(tap: .cghidEventTap)
}

func postKey(_ code: CGKeyCode, _ extra: CGEventFlags) {
    for down in [true, false] {
        let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down)
        event?.flags = held.union(extra)
        event?.post(tap: .cghidEventTap)
    }
}

func postMouse(_ type: CGEventType, _ point: CGPoint) {
    CGEvent(
        mouseEventSource: source, mouseType: type,
        mouseCursorPosition: point, mouseButton: .left
    )?.post(tap: .cghidEventTap)
}

/// The largest window belonging to `owner`, in window server coordinates. Used
/// both to find the overlay and to measure a window that was just moved.
func window(owner: String, minimumWidth: CGFloat) -> String? {
    let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
    let listing = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []

    var best: (id: Int, rect: CGRect)?
    for entry in listing {
        guard (entry[kCGWindowOwnerName as String] as? String) == owner,
              let raw = entry[kCGWindowBounds as String],
              let rect = CGRect(dictionaryRepresentation: raw as! CFDictionary),
              rect.width >= minimumWidth,
              let id = entry[kCGWindowNumber as String] as? Int
        else { continue }

        if best == nil || rect.width * rect.height > best!.rect.width * best!.rect.height {
            best = (id, rect)
        }
    }

    guard let best else { return nil }

    return "\(best.id) \(Int(best.rect.minX)) \(Int(best.rect.minY)) "
        + "\(Int(best.rect.width)) \(Int(best.rect.height))"
}

var arguments = Array(CommandLine.arguments.dropFirst())

func next() -> String {
    guard !arguments.isEmpty else {
        FileHandle.standardError.write(Data("missing argument\n".utf8))
        exit(2)
    }
    return arguments.removeFirst()
}

while !arguments.isEmpty {
    switch next() {
    case "hold":
        postFlags(flags(next()))
    case "release":
        postFlags([])
    case "key":
        let name = next()
        guard let code = keys[name] ?? CGKeyCode(name) else {
            FileHandle.standardError.write(Data("unknown key: \(name)\n".utf8))
            exit(2)
        }
        postKey(code, [])
    case "chord":
        // A key with modifiers that are not held across the rest of the run.
        let extra = flags(next())
        let name = next()
        guard let code = keys[name] ?? CGKeyCode(name) else {
            FileHandle.standardError.write(Data("unknown key: \(name)\n".utf8))
            exit(2)
        }
        postKey(code, extra)
    case "move":
        postMouse(.mouseMoved, CGPoint(x: Double(next())!, y: Double(next())!))
    case "click":
        let point = CGPoint(x: Double(next())!, y: Double(next())!)
        postMouse(.leftMouseDown, point)
        postMouse(.leftMouseUp, point)
    case "wait":
        usleep(UInt32(Double(next())! * 1000))
    case "window":
        let owner = next()
        var minimum = 0.0
        if let candidate = arguments.first, let value = Double(candidate) {
            minimum = value
            _ = next()
        }
        print(window(owner: owner, minimumWidth: minimum) ?? "")
    case "tile":
        // The centre of tile <index>, from the panel's rect. Worked out here
        // rather than asked of Flip, so a layout that drifts is caught rather
        // than agreed with. Aiming at the panel's own middle does not do: with
        // two rows that lands in the gap between them, where nothing is.
        let index = Int(next())!, count = Int(next())!
        let px = Double(next())!, py = Double(next())!
        let pw = Double(next())!, ph = Double(next())!
        let tileWidth = 300.0, ratio = 0.58, titleHeight = 34.0
        let tilePad = 14.0, panelPad = 18.0, fraction = 0.92

        var rows = 1
        for threshold in [5, 12] where count > threshold { rows += 1 }
        let columns = Int((Double(count) / Double(rows)).rounded(.up))
        let usable = pw * fraction - panelPad * 2 - tilePad * Double(columns - 1)
        let w = min(tileWidth, usable / Double(columns))
        let h = (w * ratio).rounded(.down) + titleHeight
        let gridW = Double(columns) * w + tilePad * Double(columns - 1) + panelPad * 2
        let gridH = Double(rows) * h + tilePad * Double(rows - 1) + panelPad * 2

        let row = index / columns, column = index % columns
        let inRow = min(count - row * columns, columns)
        let indent = Double(columns - inRow) * (w + tilePad) / 2
        let x = px + (pw - gridW) / 2 + panelPad + indent
            + Double(column) * (w + tilePad) + w / 2
        let y = py + (ph - gridH) / 2 + panelPad + Double(row) * (h + tilePad) + h / 2
        print(Int(x), Int(y))
    case "axwindow":
        // Through accessibility, not the window server. Stage Manager parks a
        // window as a 200 point miniature and the window server reports that as
        // the window — which makes measuring an arrangement impossible. AX keeps
        // reporting the real geometry throughout.
        let name = next()
        var printed = false
        if let app = NSWorkspace.shared.runningApplications.first(where: {
            $0.localizedName == name
        }) {
            let element = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(element, 2)
            var raw: CFTypeRef?
            AXUIElementCopyAttributeValue(element, kAXWindowsAttribute as CFString, &raw)
            if let first = (raw as? [AXUIElement])?.first {
                var positionValue: CFTypeRef?
                var sizeValue: CFTypeRef?
                AXUIElementCopyAttributeValue(first, kAXPositionAttribute as CFString, &positionValue)
                AXUIElementCopyAttributeValue(first, kAXSizeAttribute as CFString, &sizeValue)
                var origin = CGPoint.zero
                var size = CGSize.zero
                if let positionValue { AXValueGetValue(positionValue as! AXValue, .cgPoint, &origin) }
                if let sizeValue { AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) }
                print(Int(origin.x), Int(origin.y), Int(size.width), Int(size.height))
                printed = true
            }
        }
        if !printed { print("") }
    case "frontmost":
        print(NSWorkspace.shared.frontmostApplication?.localizedName ?? "?")
    default:
        FileHandle.standardError.write(Data("unknown command\n".utf8))
        exit(2)
    }
}
