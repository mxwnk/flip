import AppKit
import Carbon.HIToolbox
import CoreGraphics

enum WindowArrangement: CaseIterable {
    case leftHalf
    case rightHalf
    case topHalf
    case bottomHalf
    case topLeftQuarter
    case topRightQuarter
    case bottomLeftQuarter
    case bottomRightQuarter
    case maximize
    case previousDisplay
    case nextDisplay

    /// What `flip arrange` calls these. A test holds this to the names in
    /// FlipControl, so neither side can gain one the other does not know.
    var controlName: String {
        switch self {
        case .leftHalf: return "left-half"
        case .rightHalf: return "right-half"
        case .topHalf: return "top-half"
        case .bottomHalf: return "bottom-half"
        case .topLeftQuarter: return "top-left"
        case .topRightQuarter: return "top-right"
        case .bottomLeftQuarter: return "bottom-left"
        case .bottomRightQuarter: return "bottom-right"
        case .maximize: return "fill"
        case .previousDisplay: return "previous-display"
        case .nextDisplay: return "next-display"
        }
    }

    init?(controlName: String) {
        guard let match = Self.allCases.first(where: { $0.controlName == controlName })
        else { return nil }

        self = match
    }
}

/// One action and its key. The router matches against this and the settings
/// window lists it, so the two cannot drift apart.
struct WindowShortcut: Identifiable {
    let arrangement: WindowArrangement
    let modifiers: CGEventFlags
    let keyCode: CGKeyCode
    let name: String
    let keys: String

    var id: String { keys }
}

extension WindowArrangement {
    /// On the table rather than inside the router, so the router and its tests
    /// ask the same question.
    static func matching(
        keyCode: CGKeyCode,
        modifiers: CGEventFlags,
        displayMove: DisplayMoveModifier
    ) -> WindowArrangement? {
        shortcuts(displayMove: displayMove)
            .first { $0.keyCode == keyCode && $0.modifiers == Modifiers.significant(in: modifiers) }?
            .arrangement
    }

    /// Halves and quarters are fixed: every single modifier is already taken on
    /// the arrows, so a pair is all that is left and there is no second one. The
    /// display moves share those arrows, hence a modifier of their own.
    ///
    /// Corners take `u i j k` because those form a square on the keyboard —
    /// vim's `y u / h j` only does on a US layout.
    static func shortcuts(displayMove: DisplayMoveModifier) -> [WindowShortcut] {
        let halves: CGEventFlags = [.maskControl, .maskAlternate]
        let displays = displayMove.flags
        let move = displayMove.symbols

        return [
            WindowShortcut(arrangement: .leftHalf, modifiers: halves,
                           keyCode: CGKeyCode(kVK_LeftArrow), name: "Left half", keys: "⌃⌥←"),
            WindowShortcut(arrangement: .rightHalf, modifiers: halves,
                           keyCode: CGKeyCode(kVK_RightArrow), name: "Right half", keys: "⌃⌥→"),
            WindowShortcut(arrangement: .topHalf, modifiers: halves,
                           keyCode: CGKeyCode(kVK_UpArrow), name: "Top half", keys: "⌃⌥↑"),
            WindowShortcut(arrangement: .bottomHalf, modifiers: halves,
                           keyCode: CGKeyCode(kVK_DownArrow), name: "Bottom half", keys: "⌃⌥↓"),
            WindowShortcut(arrangement: .topLeftQuarter, modifiers: halves,
                           keyCode: CGKeyCode(kVK_ANSI_U), name: "Top left quarter", keys: "⌃⌥U"),
            WindowShortcut(arrangement: .topRightQuarter, modifiers: halves,
                           keyCode: CGKeyCode(kVK_ANSI_I), name: "Top right quarter", keys: "⌃⌥I"),
            WindowShortcut(arrangement: .bottomLeftQuarter, modifiers: halves,
                           keyCode: CGKeyCode(kVK_ANSI_J), name: "Bottom left quarter", keys: "⌃⌥J"),
            WindowShortcut(arrangement: .bottomRightQuarter, modifiers: halves,
                           keyCode: CGKeyCode(kVK_ANSI_K), name: "Bottom right quarter", keys: "⌃⌥K"),
            WindowShortcut(arrangement: .maximize, modifiers: halves,
                           keyCode: CGKeyCode(kVK_Return), name: "Fill the screen", keys: "⌃⌥↩"),
            WindowShortcut(arrangement: .previousDisplay, modifiers: displays,
                           keyCode: CGKeyCode(kVK_LeftArrow), name: "Previous display",
                           keys: "\(move)←"),
            WindowShortcut(arrangement: .nextDisplay, modifiers: displays,
                           keyCode: CGKeyCode(kVK_RightArrow), name: "Next display",
                           keys: "\(move)→"),
        ]
    }
}

@MainActor
enum WindowArranger {
    /// What a keypress should do, given where the window is now.
    struct Outcome: Equatable {
        var target: CGRect?
        /// Where to put the window back next time, or nil to forget.
        var restore: CGRect?
    }

    /// Where the window should end up, in Cocoa coordinates. Measured against
    /// `visibleFrame`, so a maximised window stops at the menu bar and the Dock.
    static func outcome(
        for arrangement: WindowArrangement,
        window: CGRect,
        remembered: CGRect?
    ) -> Outcome {
        guard let screen = ScreenGeometry.screen(containing: window) else { return Outcome() }

        switch arrangement {
        case .nextDisplay: return Outcome(target: moved(window, from: screen, by: 1))
        case .previousDisplay: return Outcome(target: moved(window, from: screen, by: -1))
        default:
            return outcome(
                for: arrangement, window: window,
                in: screen.visibleFrame, remembered: remembered
            )
        }
    }

    /// Filling a window that already fills puts it back. Every other arrangement
    /// is one-way and forgets the remembered frame, so it cannot outlive its fill.
    nonisolated static func outcome(
        for arrangement: WindowArrangement,
        window: CGRect,
        in area: CGRect,
        remembered: CGRect?
    ) -> Outcome {
        guard arrangement == .maximize else {
            return Outcome(target: frame(for: arrangement, in: area))
        }

        guard fills(window, area) else {
            return Outcome(target: area, restore: window)
        }

        // Nothing remembered: the window already filled when Flip first saw it.
        // Something reasonable beats refusing to move.
        return Outcome(target: remembered ?? centred(in: area))
    }

    /// Applications that resize in steps cannot land on the visible frame exactly
    /// — a terminal snaps to whole character cells — and a few points short still
    /// counts as filled to whoever pressed the key.
    nonisolated static func fills(_ window: CGRect, _ area: CGRect, tolerance: CGFloat = 20) -> Bool {
        abs(window.minX - area.minX) <= tolerance
            && abs(window.minY - area.minY) <= tolerance
            && abs(window.width - area.width) <= tolerance
            && abs(window.height - area.height) <= tolerance
    }

    private nonisolated static func centred(in area: CGRect) -> CGRect {
        let size = CGSize(width: area.width * 0.6, height: area.height * 0.6)

        return CGRect(
            x: area.midX - size.width / 2, y: area.midY - size.height / 2,
            width: size.width, height: size.height
        )
    }

    /// The geometry alone, so it can be checked without a screen. `area` is a
    /// visible frame: no menu bar, no Dock, and its origin is not necessarily zero.
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
        case .topLeftQuarter:
            return CGRect(x: area.minX, y: area.midY, width: area.width / 2, height: area.height / 2)
        case .topRightQuarter:
            return CGRect(x: area.midX, y: area.midY, width: area.width / 2, height: area.height / 2)
        case .bottomLeftQuarter:
            return CGRect(x: area.minX, y: area.minY, width: area.width / 2, height: area.height / 2)
        case .bottomRightQuarter:
            return CGRect(x: area.midX, y: area.minY, width: area.width / 2, height: area.height / 2)
        case .maximize:
            return area
        case .nextDisplay, .previousDisplay:
            return nil
        }
    }

    private static func moved(_ window: CGRect, from screen: NSScreen, by step: Int) -> CGRect? {
        let screens = NSScreen.screens
        guard screens.count > 1, let index = screens.firstIndex(of: screen) else { return nil }

        let target = screens[(index + step % screens.count + screens.count) % screens.count]

        return mapped(window, from: screen.visibleFrame, to: target.visibleFrame)
    }

    /// Proportional, so a left half stays a left half rather than landing
    /// somewhere arbitrary. Pure, so it needs no second monitor to check.
    nonisolated static func mapped(_ window: CGRect, from: CGRect, to: CGRect) -> CGRect {
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
