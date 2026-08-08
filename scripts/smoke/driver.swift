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
//
// That single invocation is also why the `await` commands live here rather than
// in the shell: the sequence cannot be cut in half to poll from outside, because
// a fresh process posts its key events with no modifier held and the switcher
// would see the arrow key without the Option that is holding it open.

import AppKit
import CoreGraphics

let source = CGEventSource(stateID: .hidSystemState)

/// Poll until something is true, rather than sleeping long enough that it must
/// be. Every wait in the suite used to be a flat sleep sized for the worst case
/// on the slowest machine; polling costs the actual case and can afford a far
/// more generous ceiling, so the suite got both quicker and harder to make flaky.
func poll(timeout milliseconds: Double, every step: UInt32 = 20_000, until ready: () -> Bool) -> Bool {
    posted = false
    let deadline = Date().addingTimeInterval(milliseconds / 1000)
    repeat {
        if ready() { return true }
        usleep(step)
    } while Date() < deadline

    return ready()
}

/// The log Flip is writing into, and how far into it this step has already been
/// told to ignore. Passed in the environment so the argument lists stay readable.
let logPath = ProcessInfo.processInfo.environment["SMOKE_LOG"]
let logMark = Int(ProcessInfo.processInfo.environment["SMOKE_MARK"] ?? "0") ?? 0

/// Whether the log has said this since the mark. Reading the file each time is
/// cheaper than it looks — the predicate is Flip's subsystem alone, so it holds
/// kilobytes, not the megabytes an unfiltered stream would.
func logged(_ pattern: String) -> Bool {
    guard let logPath, let regex = try? NSRegularExpression(pattern: pattern),
          let data = FileManager.default.contents(atPath: logPath), data.count > logMark
    else { return false }

    let text = String(decoding: data[logMark...], as: UTF8.self)

    return regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
}

/// What accessibility reports for an application's first window, which is the
/// only way to measure an arrangement with Stage Manager on.
func axFrame(of name: String) -> CGRect? {
    guard let app = NSWorkspace.shared.runningApplications.first(where: {
        $0.localizedName == name
    }) else { return nil }

    let element = AXUIElementCreateApplication(app.processIdentifier)
    AXUIElementSetMessagingTimeout(element, 2)

    var raw: CFTypeRef?
    AXUIElementCopyAttributeValue(element, kAXWindowsAttribute as CFString, &raw)
    guard let first = (raw as? [AXUIElement])?.first else { return nil }

    var positionValue: CFTypeRef?
    var sizeValue: CFTypeRef?
    AXUIElementCopyAttributeValue(first, kAXPositionAttribute as CFString, &positionValue)
    AXUIElementCopyAttributeValue(first, kAXSizeAttribute as CFString, &sizeValue)

    var origin = CGPoint.zero
    var size = CGSize.zero
    if let positionValue { AXValueGetValue(positionValue as! AXValue, .cgPoint, &origin) }
    if let sizeValue { AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) }

    return CGRect(origin: origin, size: size)
}

func describe(_ rect: CGRect) -> String {
    "\(Int(rect.minX)) \(Int(rect.minY)) \(Int(rect.width)) \(Int(rect.height))"
}

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

/// Whether an event has been posted with nothing waited for since. Posting is
/// asynchronous — it hands the event to the window server — so an invocation
/// that exits in the same breath can take the event down with it. Measured: a
/// fill chord posted by an invocation ending right there moved nothing at all,
/// three times running, while the same chord followed by any wait moved the
/// window every time.
///
/// Every wait clears it, so a sequence that already ends by waiting for
/// something costs nothing for this.
var posted = false

func postFlags(_ value: CGEventFlags) {
    held = value
    let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true)
    event?.type = .flagsChanged
    event?.flags = value
    event?.post(tap: .cghidEventTap)
    posted = true
}

func postKey(_ code: CGKeyCode, _ extra: CGEventFlags) {
    for down in [true, false] {
        let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down)
        event?.flags = held.union(extra)
        event?.post(tap: .cghidEventTap)
    }
    posted = true
}

func postMouse(_ type: CGEventType, _ point: CGPoint) {
    CGEvent(
        mouseEventSource: source, mouseType: type,
        mouseCursorPosition: point, mouseButton: .left
    )?.post(tap: .cghidEventTap)
    posted = true
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
        posted = false
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
        print(axFrame(of: next()).map(describe) ?? "")
    case "frontmost":
        print(NSWorkspace.shared.frontmostApplication?.localizedName ?? "?")

    // ------------------------------------------------------------------ waiting

    case "await":
        // Waits for a line, and says nothing either way: the check that follows
        // still reads the log and decides. So a timeout here fails exactly the
        // check a too-short sleep used to fail — only after a ceiling nobody has
        // to tune, instead of a sleep everybody does.
        let pattern = next()
        _ = poll(timeout: Double(next())!) { logged(pattern) }
    case "awaitwindow":
        // Blocks until the window exists, then prints it exactly as `window`
        // does, so callers read the same five fields out of either.
        let owner = next()
        let minimum = Double(next())!
        let timeout = Double(next())!
        var found: String?
        _ = poll(timeout: timeout, every: 50_000) {
            found = window(owner: owner, minimumWidth: minimum)
            return found != nil
        }
        print(found ?? "")
    case "awaitfront":
        let name = next()
        let timeout = Double(next())!
        let arrived = poll(timeout: timeout, every: 50_000) {
            NSWorkspace.shared.frontmostApplication?.localizedName == name
        }
        print(arrived ? "yes" : "no")
    case "awaitax":
        // Waits for an arrangement to land by watching the width change, rather
        // than sleeping long enough that it must have. The settle first is not
        // superstition: without it a window that already happens to satisfy the
        // comparison returns the old reading before the key is even handled.
        let name = next()
        let comparison = next()
        let value = Double(next())!
        let timeout = Double(next())!
        usleep(150_000)

        var last: CGRect?
        _ = poll(timeout: timeout, every: 50_000) {
            guard let rect = axFrame(of: name) else { return false }
            last = rect
            switch comparison {
            case "gt": return rect.width > value
            case "lt": return rect.width < value
            case "ne": return rect.width != value
            default: return true
            }
        }
        print(last.map(describe) ?? "")
    default:
        FileHandle.standardError.write(Data("unknown command\n".utf8))
        exit(2)
    }
}

// Nothing waited after the last event, so give the window server the moment it
// needs to take delivery before this process disappears.
if posted { usleep(150_000) }
