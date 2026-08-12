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

    /// Spelled out under the symbols, for the same reason the keyboard picture
    /// spells them out: ⌃⌥⌘ mean nothing until you have read them once.
    var spelled: String {
        switch self {
        case .option: return "option"
        case .control: return "control"
        case .command: return "command"
        case .optionControl: return "control option"
        case .optionCommand: return "option command"
        case .controlCommand: return "control command"
        }
    }

    /// Command and a letter is a menu shortcut in every application there is.
    var takesMenuShortcuts: Bool { flags.contains(.maskCommand) }
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

/// Which screen the grid appears on. On a two monitor desk it can otherwise
/// open on the display you are not looking at, reading as though nothing happened.
enum OverlayPlacement: String, Codable, CaseIterable, Identifiable {
    case activeWindow
    case primaryDisplay
    case everyDisplay

    var id: String { rawValue }

    var label: String {
        switch self {
        case .activeWindow: return "The display with the active window"
        case .primaryDisplay: return "The main display"
        case .everyDisplay: return "Every display"
        }
    }
}

/// Which modifier carries a window to the next display — apart from the halves,
/// which own Control and Option on the same arrows.
enum DisplayMoveModifier: String, Codable, CaseIterable, Identifiable {
    case shiftOption
    case allThree

    var id: String { rawValue }

    var flags: CGEventFlags {
        switch self {
        case .shiftOption: return [.maskShift, .maskAlternate]
        case .allThree: return [.maskControl, .maskAlternate, .maskCommand]
        }
    }

    var symbols: String {
        switch self {
        case .shiftOption: return "⇧⌥"
        case .allThree: return "⌃⌥⌘"
        }
    }

    var label: String {
        switch self {
        case .shiftOption: return "⇧⌥ and the arrows"
        case .allThree: return "⌃⌥⌘ and the arrows"
        }
    }
}

/// Where command sits in the bottom row. macOS cannot be asked: its modifier
/// remapping says what each key *does*, not where it *is*, and the Nuphy Air75
/// reports Apple's vendor identifier while carrying the Windows arrangement.
enum ModifierRowOrder: String, Codable, CaseIterable, Identifiable {
    case appleStyle
    case windowsStyle

    var id: String { rawValue }

    var label: String {
        switch self {
        case .appleStyle: return "⌃ ⌥ ⌘"
        case .windowsStyle: return "⌃ ⌘ ⌥"
        }
    }
}

struct Settings: Codable, Equatable {
    var leader: ModifierChoice = .option

    var appSwitcher: ModifierChoice = .command

    /// What the application keys answer to. Its own setting rather than the
    /// switcher's leader, which it used to share: one is tapped and let go, the
    /// other is held while you read a grid, and on a board with a Windows bottom
    /// row they are not even in the places their names suggest.
    var shortcutLeader: ModifierChoice = .option

    /// Off needs no Screen Recording grant at all.
    var showThumbnails = true

    /// A shorter tap switches with no overlay. The selection is made either
    /// way; only showing it waits.
    var overlayDelay: OverlayDelay = .short

    /// Off lists only what is on the space you are looking at.
    var showWindowsFromEverySpace = false

    var overlayPlacement: OverlayPlacement = .activeWindow

    /// Only the display moves are settable — see WindowArrangement for why.
    var displayMoveModifier: DisplayMoveModifier = .shiftOption

    /// Only affects the picture of the keyboard in the settings window.
    var modifierRowOrder: ModifierRowOrder = .appleStyle

    /// The only thing Flip ever sends a request for.
    var checkForUpdates = true

    /// Kept out of the all-windows list. A key bound directly still reaches them.
    var excludedBundleIDs: [String] = []

    var isValid: Bool { leader != appSwitcher }

    init() {}

    /// Every field falls back instead of failing: synthesised decoding requires
    /// all keys, so adding one would silently reset an existing file.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Settings()

        leader = try container.decodeIfPresent(ModifierChoice.self, forKey: .leader)
            ?? defaults.leader
        appSwitcher = try container.decodeIfPresent(ModifierChoice.self, forKey: .appSwitcher)
            ?? defaults.appSwitcher
        // Falls back to the leader rather than to the default: a file written
        // before the two were separable meant the leader, and a constant here
        // would move every application key on the first launch after an update.
        shortcutLeader = try container.decodeIfPresent(ModifierChoice.self, forKey: .shortcutLeader)
            ?? leader
        showThumbnails = try container.decodeIfPresent(Bool.self, forKey: .showThumbnails)
            ?? defaults.showThumbnails
        overlayDelay = try container.decodeIfPresent(OverlayDelay.self, forKey: .overlayDelay)
            ?? defaults.overlayDelay
        showWindowsFromEverySpace = try container
            .decodeIfPresent(Bool.self, forKey: .showWindowsFromEverySpace)
            ?? defaults.showWindowsFromEverySpace
        overlayPlacement = try container
            .decodeIfPresent(OverlayPlacement.self, forKey: .overlayPlacement)
            ?? defaults.overlayPlacement
        displayMoveModifier = try container
            .decodeIfPresent(DisplayMoveModifier.self, forKey: .displayMoveModifier)
            ?? defaults.displayMoveModifier
        modifierRowOrder = try container
            .decodeIfPresent(ModifierRowOrder.self, forKey: .modifierRowOrder)
            ?? defaults.modifierRowOrder
        checkForUpdates = try container.decodeIfPresent(Bool.self, forKey: .checkForUpdates)
            ?? defaults.checkForUpdates
        excludedBundleIDs = try container.decodeIfPresent([String].self, forKey: .excludedBundleIDs)
            ?? defaults.excludedBundleIDs
    }
}
