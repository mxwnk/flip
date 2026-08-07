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

    /// Off lists only what is on the space you are looking at.
    var showWindowsFromEverySpace = false

    /// Kept out of the all-windows list. A key bound directly still reaches them.
    var excludedBundleIDs: [String] = []

    var isValid: Bool { leader != appSwitcher }

    init() {}

    /// Every field falls back instead of failing. Swift's synthesised decoding
    /// requires all keys, so adding one would make an existing file unreadable and
    /// silently reset everything the user had configured.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Settings()

        leader = try container.decodeIfPresent(ModifierChoice.self, forKey: .leader)
            ?? defaults.leader
        appSwitcher = try container.decodeIfPresent(ModifierChoice.self, forKey: .appSwitcher)
            ?? defaults.appSwitcher
        showThumbnails = try container.decodeIfPresent(Bool.self, forKey: .showThumbnails)
            ?? defaults.showThumbnails
        overlayDelay = try container.decodeIfPresent(OverlayDelay.self, forKey: .overlayDelay)
            ?? defaults.overlayDelay
        showWindowsFromEverySpace = try container
            .decodeIfPresent(Bool.self, forKey: .showWindowsFromEverySpace)
            ?? defaults.showWindowsFromEverySpace
        excludedBundleIDs = try container.decodeIfPresent([String].self, forKey: .excludedBundleIDs)
            ?? defaults.excludedBundleIDs
    }
}
