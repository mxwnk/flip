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
    /// The lookup the router performs, on the table rather than inside it, so both
    /// the router and its tests ask the same question.
    static func matching(
        keyCode: CGKeyCode,
        modifiers: CGEventFlags,
        displayMove: DisplayMoveModifier
    ) -> WindowArrangement? {
        shortcuts(displayMove: displayMove)
            .first { $0.keyCode == keyCode && $0.modifiers == Modifiers.significant(in: modifiers) }?
            .arrangement
    }

    /// The halves and quarters are fixed, and stay that way. Every single modifier
    /// is already spoken for with the arrow keys — Option moves by word, Control
    /// switches spaces, fn is Home and End, and Command is start and end of line —
    /// so two of them is what is left, and there is no second pair to offer.
    ///
    /// The display moves are the exception: they take the same arrows as the
    /// halves, so they need a modifier of their own, and which one is a matter of
    /// what else is bound on the machine.
    ///
    /// Corners take letters rather than arrows: four corners need four keys and
    /// arrows only offer two axes. `u i j k` because those four sit as a square on
    /// the keyboard, which the obvious vim choice does not — `y u / h j` looks like
    /// a square on a US layout but types `z u / h j` on a German one, putting the
    /// top left corner on the wrong key.
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

    /// Where the window should end up, in Cocoa coordinates.
    ///
    /// Everything is measured against `visibleFrame`, so a maximised window stops
    /// at the menu bar and the Dock rather than hiding behind them.
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

    /// Filling a window that already fills puts it back where it was. Every other
    /// arrangement is one-way and forgets whatever was being held for a restore,
    /// so a remembered frame can never outlive the fill it belongs to.
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

        // Nothing remembered means the window was already filling when Flip first
        // saw it — a restart, or the application opened that way. Something
        // reasonable beats refusing to move.
        return Outcome(target: remembered ?? centred(in: area))
    }

    /// Applications that resize in steps cannot land on the visible frame exactly
    /// — a terminal snaps to whole character cells — and a window a few points
    /// short of the edges is filled as far as anyone pressing the key is concerned.
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

    /// Keeps the window where it was on the display it leaves, proportionally, so a
    /// left half stays a left half rather than landing somewhere arbitrary. Pure,
    /// so it can be checked without a second monitor.
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
