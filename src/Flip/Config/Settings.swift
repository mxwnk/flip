import CoreGraphics
import Foundation

/// A protocol rather than one enum, because what a leader may be and what a
/// window action may be are different sets.
protocol LeaderChoice: CaseIterable, Hashable, Identifiable {
    var label: String { get }
    /// ⌃⌥⌘ mean nothing until read once.
    var spelled: String { get }
}

/// Closed: a leader with no modifier would swallow ordinary typing.
enum ModifierChoice: String, Codable, CaseIterable, Identifiable, LeaderChoice {
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

    /// One modifier and an arrow is taken by macOS: option by word, control
    /// spaces, command line ends. Two is what is left.
    var takesArrowKeys: Bool {
        switch self {
        case .option, .control, .command: return true
        case .optionControl, .optionCommand, .controlCommand: return false
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

/// Which screen the grid appears on. Otherwise it can open on the display you
/// are not looking at.
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

/// Shares the arrows with the halves, so the two must differ. Neither is
/// expressible as a `ModifierChoice`, so they cannot collide.
enum DisplayMoveModifier: String, Codable, CaseIterable, Identifiable, LeaderChoice {
    case shiftOption
    case allThree

    var id: String { rawValue }

    var flags: CGEventFlags {
        switch self {
        case .shiftOption: return [.maskShift, .maskAlternate]
        case .allThree: return [.maskControl, .maskAlternate, .maskCommand]
        }
    }

    var label: String {
        switch self {
        case .shiftOption: return "⇧⌥"
        case .allThree: return "⌃⌥⌘"
        }
    }

    var spelled: String {
        switch self {
        case .shiftOption: return "shift option"
        case .allThree: return "control option command"
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
    /// ⌘Tab is the switcher every Mac user already reaches for, so that is the
    /// one that shows everything. Flip only changes what it lists: windows
    /// rather than applications.
    var leader: ModifierChoice = .command

    /// ⌥Tab narrows to the application in front, where stock macOS uses ⌘` — a
    /// key half the keyboards in Europe put somewhere else.
    var appSwitcher: ModifierChoice = .option

    /// Its own setting, not the switcher's leader: one is tapped and let go, the
    /// other is held while you read a grid.
    var shortcutLeader: ModifierChoice = .option

    /// Off needs no Screen Recording grant at all.
    var showThumbnails = true

    /// A shorter tap switches with no overlay; only showing it waits.
    var overlayDelay: OverlayDelay = .short

    /// Off lists only what is on the space you are looking at.
    var showWindowsFromEverySpace = false

    var overlayPlacement: OverlayPlacement = .activeWindow

    var displayMoveModifier: DisplayMoveModifier = .shiftOption

    /// Two modifiers, for the reason in `takesArrowKeys`; which two is open.
    var windowLeader: ModifierChoice = .optionControl

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
        // A file written before these were separable meant the leader, so a
        // constant here would move every application key on the next launch.
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
        // What the halves were nailed to before they were settable.
        windowLeader = try container.decodeIfPresent(ModifierChoice.self, forKey: .windowLeader)
            ?? defaults.windowLeader
        modifierRowOrder = try container
            .decodeIfPresent(ModifierRowOrder.self, forKey: .modifierRowOrder)
            ?? defaults.modifierRowOrder
        checkForUpdates = try container.decodeIfPresent(Bool.self, forKey: .checkForUpdates)
            ?? defaults.checkForUpdates
        excludedBundleIDs = try container.decodeIfPresent([String].self, forKey: .excludedBundleIDs)
            ?? defaults.excludedBundleIDs
    }
}
