import AppKit
import Carbon.HIToolbox
import CoreGraphics

/// The raw value is the one name this arrangement has: `flip arrange <name>`
/// takes it, config.json keys its shortcut by it, and a test holds it to
/// FlipControl, which cannot see this type.
enum WindowArrangement: String, CaseIterable, Codable, CodingKeyRepresentable {
    case leftHalf = "left-half"
    case rightHalf = "right-half"
    case topHalf = "top-half"
    case bottomHalf = "bottom-half"
    case topLeftQuarter = "top-left"
    case topRightQuarter = "top-right"
    case bottomLeftQuarter = "bottom-left"
    case bottomRightQuarter = "bottom-right"
    case maximize
    case previousDisplay = "previous-display"
    case nextDisplay = "next-display"

    /// Between displays, not within one, and on their own modifier.
    var movesToAnotherDisplay: Bool {
        switch self {
        case .previousDisplay, .nextDisplay: return true
        default: return false
        }
    }

    /// What the settings window calls it.
    var title: String {
        switch self {
        case .leftHalf: return "Left half"
        case .rightHalf: return "Right half"
        case .topHalf: return "Top half"
        case .bottomHalf: return "Bottom half"
        case .topLeftQuarter: return "Top left quarter"
        case .topRightQuarter: return "Top right quarter"
        case .bottomLeftQuarter: return "Bottom left quarter"
        case .bottomRightQuarter: return "Bottom right quarter"
        case .maximize: return "Maximize"
        case .previousDisplay: return "Previous display"
        case .nextDisplay: return "Next display"
        }
    }

    /// The keys out of the box. Corners are `u i j k` because those form a
    /// square; vim's `y u / h j` only does on a US layout.
    static let defaultKeys: [WindowArrangement: String] = [
        .leftHalf: "left",
        .rightHalf: "right",
        .topHalf: "up",
        .bottomHalf: "down",
        .topLeftQuarter: "u",
        .topRightQuarter: "i",
        .bottomLeftQuarter: "j",
        .bottomRightQuarter: "k",
        .maximize: "return",
        .previousDisplay: "left",
        .nextDisplay: "right",
    ]
}

/// The router matches against this and the settings window lists it.
struct WindowShortcut: Identifiable {
    let arrangement: WindowArrangement
    let modifiers: CGEventFlags
    let keyCode: CGKeyCode
    let name: String
    let keys: String

    var id: String { arrangement.rawValue }
}

extension WindowArrangement {
    /// On the table, so the router and its tests ask the same question.
    static func matching(
        keyCode: CGKeyCode,
        modifiers: CGEventFlags,
        leader: ModifierChoice,
        displayMove: DisplayMoveModifier,
        keys: [WindowArrangement: String] = defaultKeys
    ) -> WindowArrangement? {
        shortcuts(leader: leader, displayMove: displayMove, keys: keys)
            .first { $0.keyCode == keyCode && $0.modifiers == Modifiers.significant(in: modifiers) }?
            .arrangement
    }

    /// Both the modifiers and the keys are settings; which of the two modifiers
    /// a row carries is not, since only the display moves may share the arrows.
    static func shortcuts(
        leader: ModifierChoice,
        displayMove: DisplayMoveModifier,
        keys: [WindowArrangement: String] = defaultKeys
    ) -> [WindowShortcut] {
        allCases.compactMap { arrangement in
            guard let key = keys[arrangement],
                  let code = KeyboardLayout.keyCode(forBinding: key)
            else { return nil }

            let displaced = arrangement.movesToAnotherDisplay
            let flags = displaced ? displayMove.flags : leader.flags
            let label = displaced ? displayMove.label : leader.label

            return WindowShortcut(
                arrangement: arrangement, modifiers: flags, keyCode: code,
                name: arrangement.title, keys: label + KeyboardLayout.symbol(forBinding: key)
            )
        }
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

        // Already filled when Flip first saw it; moving beats refusing to.
        return Outcome(target: remembered ?? centred(in: area))
    }

    /// A terminal snaps to whole character cells, so a few points short still
    /// counts as filled.
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

    /// Geometry alone, checkable without a screen. `area` is a visible frame,
    /// so its origin is not necessarily zero.
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

    /// Proportional, so a left half stays a left half. Pure, so it needs no
    /// second monitor to check.
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
