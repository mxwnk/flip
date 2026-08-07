import CoreGraphics
import Foundation

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

/// How long the leader must be held before the overlay appears.
enum OverlayDelay: String, Codable, CaseIterable, Identifiable {
    case immediately
    case short
    case long

    var id: String { rawValue }

    var seconds: TimeInterval {
        switch self {
        case .immediately: return 0
        case .short: return 0.15
        case .long: return 0.3
        }
    }

    var label: String {
        switch self {
        case .immediately: return "Immediately"
        case .short: return "After 150 ms"
        case .long: return "After 300 ms"
        }
    }
}

struct Settings: Codable, Equatable {
    var leader: ModifierChoice = .option

    var appSwitcher: ModifierChoice = .command

    /// Off needs no Screen Recording grant at all.
    var showThumbnails = true

    /// A tap shorter than this switches with no overlay at all. The selection is
    /// made either way; only showing it waits.
    var overlayDelay: OverlayDelay = .short

    /// Kept out of the all-windows list. A key bound directly still reaches them.
    var excludedBundleIDs: [String] = []

    var isValid: Bool { leader != appSwitcher }
}
