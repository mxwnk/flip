import CoreGraphics

/// Modifier combinations offered for the two hotkeys.
///
/// A closed set rather than free choice: the pair has to be unambiguous, and a
/// leader with no modifier at all would swallow ordinary typing.
enum ModifierChoice: String, Codable, CaseIterable, Identifiable {
    case option
    case control
    case command
    case optionControl = "option-control"
    case optionCommand = "option-command"
    case controlCommand = "control-command"

    var id: String { rawValue }

    var flags: CGEventFlags {
        switch self {
        case .option: return [.maskAlternate]
        case .control: return [.maskControl]
        case .command: return [.maskCommand]
        case .optionControl: return [.maskAlternate, .maskControl]
        case .optionCommand: return [.maskAlternate, .maskCommand]
        case .controlCommand: return [.maskControl, .maskCommand]
        }
    }

    var label: String {
        switch self {
        case .option: return "⌥"
        case .control: return "⌃"
        case .command: return "⌘"
        case .optionControl: return "⌃⌥"
        case .optionCommand: return "⌥⌘"
        case .controlCommand: return "⌃⌘"
        }
    }
}

struct Settings: Codable, Equatable {
    /// Held for the whole interaction: opens the switcher, keeps it open, and
    /// releasing it commits.
    var leader: ModifierChoice = .option

    /// Cycles the frontmost application's own windows.
    var appSwitcher: ModifierChoice = .command

    /// Off makes the overlay pure icons, which is instant and needs no Screen
    /// Recording grant at all.
    var showThumbnails = true

    /// Applications kept out of the all-windows list. A key bound directly to one
    /// still reaches it — excluding an application means "not while I am cycling",
    /// not "unreachable".
    var excludedBundleIDs: [String] = []

    /// The two hotkeys must differ, or one of them can never be matched.
    var isValid: Bool { leader != appSwitcher }
}
