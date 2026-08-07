import AppKit
import Carbon.HIToolbox
import CoreGraphics

enum WindowArrangement: CaseIterable {
    case leftHalf
    case rightHalf
    case topHalf
    case bottomHalf
    case maximize
    case previousDisplay
    case nextDisplay
}

/// One action and the key that performs it. The router matches against this and
/// the settings window lists it, so the two cannot drift apart.
struct WindowShortcut: Identifiable {
    let arrangement: WindowArrangement
    let modifiers: CGEventFlags
    let keyCode: CGKeyCode
    let name: String
    let keys: String

    var id: String { keys }
}

extension WindowArrangement {
    /// Fixed for now. Every single modifier is already spoken for with the arrow
    /// keys — Option moves by word, Control switches spaces, fn is Home and End,
    /// and Command is start and end of line — so two of them is what is left.
    static let shortcuts: [WindowShortcut] = {
        let halves: CGEventFlags = [.maskControl, .maskAlternate]
        let displays: CGEventFlags = [.maskControl, .maskAlternate, .maskCommand]

        return [
            WindowShortcut(arrangement: .leftHalf, modifiers: halves,
                           keyCode: CGKeyCode(kVK_LeftArrow), name: "Left half", keys: "⌃⌥←"),
            WindowShortcut(arrangement: .rightHalf, modifiers: halves,
                           keyCode: CGKeyCode(kVK_RightArrow), name: "Right half", keys: "⌃⌥→"),
            WindowShortcut(arrangement: .topHalf, modifiers: halves,
                           keyCode: CGKeyCode(kVK_UpArrow), name: "Top half", keys: "⌃⌥↑"),
            WindowShortcut(arrangement: .bottomHalf, modifiers: halves,
                           keyCode: CGKeyCode(kVK_DownArrow), name: "Bottom half", keys: "⌃⌥↓"),
            WindowShortcut(arrangement: .maximize, modifiers: halves,
                           keyCode: CGKeyCode(kVK_Return), name: "Fill the screen", keys: "⌃⌥↩"),
            WindowShortcut(arrangement: .previousDisplay, modifiers: displays,
                           keyCode: CGKeyCode(kVK_LeftArrow), name: "Previous display", keys: "⌃⌥⌘←"),
            WindowShortcut(arrangement: .nextDisplay, modifiers: displays,
                           keyCode: CGKeyCode(kVK_RightArrow), name: "Next display", keys: "⌃⌥⌘→"),
        ]
    }()
}

@MainActor
enum WindowArranger {
    /// Where the window should end up, in Cocoa coordinates.
    ///
    /// Everything is measured against `visibleFrame`, so a maximised window stops
    /// at the menu bar and the Dock rather than hiding behind them.
    static func target(for arrangement: WindowArrangement, window: CGRect) -> CGRect? {
        guard let screen = ScreenGeometry.screen(containing: window) else { return nil }

        switch arrangement {
        case .nextDisplay: return moved(window, from: screen, by: 1)
        case .previousDisplay: return moved(window, from: screen, by: -1)
        default: return frame(for: arrangement, in: screen.visibleFrame)
        }
    }

    /// The half and maximise geometry on its own, so it can be checked without a
    /// screen. `area` is a visible frame: it excludes the menu bar and the Dock,
    /// and its origin is not necessarily zero.
    nonisolated static func frame(for arrangement: WindowArrangement, in area: CGRect) -> CGRect? {
        switch arrangement {
        case .leftHalf:
            return CGRect(x: area.minX, y: area.minY, width: area.width / 2, height: area.height)
        case .rightHalf:
            return CGRect(x: area.midX, y: area.minY, width: area.width / 2, height: area.height)
        case .topHalf:
            return CGRect(x: area.minX, y: area.midY, width: area.width, height: area.height / 2)
        case .bottomHalf:
            return CGRect(x: area.minX, y: area.minY, width: area.width, height: area.height / 2)
        case .maximize:
            return area
        case .nextDisplay, .previousDisplay:
            return nil
        }
    }

    /// Keeps the window where it was on the display it leaves, proportionally, so
    /// a left half stays a left half rather than landing somewhere arbitrary.
    private static func moved(_ window: CGRect, from screen: NSScreen, by step: Int) -> CGRect? {
        let screens = NSScreen.screens
        guard screens.count > 1, let index = screens.firstIndex(of: screen) else { return nil }

        let target = screens[(index + step % screens.count + screens.count) % screens.count]
        let from = screen.visibleFrame
        let to = target.visibleFrame

        let scaleX = to.width / from.width
        let scaleY = to.height / from.height

        return CGRect(
            x: to.minX + (window.minX - from.minX) * scaleX,
            y: to.minY + (window.minY - from.minY) * scaleY,
            width: window.width * scaleX,
            height: window.height * scaleY
        )
    }
}
