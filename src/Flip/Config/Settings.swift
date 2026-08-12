import CoreGraphics
import Foundation

/// Anything that can be picked as a leader. The picker draws keys, so it needs
/// the symbols that go on one and the words that go under it — the sets differ
/// between what a leader may be and what a window action may be, which is why
/// this is a protocol rather than one enum for both.
protocol LeaderChoice: CaseIterable, Hashable, Identifiable {
    /// The symbols on the key.
    var label: String { get }
    /// The words under them: ⌃⌥⌘ mean nothing until you have read them once.
    var spelled: String { get }
}

/// A closed set: the pair has to be unambiguous, and a leader with no modifier
/// would swallow ordinary typing.
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

    /// One modifier and an arrow is already spoken for by macOS: option moves by
    /// word, control switches spaces, command goes to the end of the line. Two of
    /// them is what is left over, which is why the window actions started there.
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

/// Which modifier carries a window to the next display. It shares the arrows
/// with the halves, so the two must differ — and they cannot collide, because
/// neither of these two is expressible as a `ModifierChoice`.
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

    var displayMoveModifier: DisplayMoveModifier = .shiftOption

    /// What the halves, quarters and filling answer to. Two modifiers is where
    /// this started and where it belongs — see `takesArrowKeys` — but which two
    /// is a matter of what else is bound on the machine.
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
        // The default is what the halves were nailed to before they were
        // settable, so an older file keeps the keys somebody's fingers know.
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
