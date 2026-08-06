import CoreGraphics

/// A closed set: the pair has to be unambiguous, and a leader with no modifier
/// would swallow ordinary typing.
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
    var leader: ModifierChoice = .option

    var appSwitcher: ModifierChoice = .command

    /// Off needs no Screen Recording grant at all.
    var showThumbnails = true

    /// Kept out of the all-windows list. A key bound directly still reaches them.
    var excludedBundleIDs: [String] = []

    var isValid: Bool { leader != appSwitcher }
}
