import Carbon.HIToolbox
import CoreGraphics
import Foundation
import OSLog

/// Turns key events into switcher commands, synchronously on the event tap's
/// thread: whether to swallow an event cannot wait for main. The interaction
/// ends on a modifier coming back up, which no hotkey API reports — hence a tap.
final class KeyRouter {
    private let presenter: SwitcherPresenting
    private let frontmost: FrontmostApp
    private let log = Logger(subsystem: Bundle.identifier, category: "router")

    /// Believing a closed overlay is open swallows arrow keys system-wide,
    /// so this crosses threads under a lock.
    private let visibility = NSLock()
    private var overlayIsVisible = false

    private var isOverlayVisible: Bool {
        get { visibility.lock(); defer { visibility.unlock() }; return overlayIsVisible }
        set { visibility.lock(); overlayIsVisible = newValue; visibility.unlock() }
    }

    /// The overlay closed without being asked: safety timeout, or nothing to show.
    func overlayDidClose() {
        isOverlayVisible = false
    }

    /// Written on main when bindings or layout change, read on the tap thread
    /// for every keystroke.
    private let bindingsLock = NSLock()
    private var leaderBindings: [CGKeyCode: String] = [:]
    private var bareBindings: [CGKeyCode: String] = [:]
    private var leaderFlags: CGEventFlags = ModifierChoice.option.flags
    private var appSwitcherFlags: CGEventFlags = ModifierChoice.command.flags
    private var displayMove: DisplayMoveModifier = .shiftOption

    init(presenter: SwitcherPresenting, frontmost: FrontmostApp) {
        self.presenter = presenter
        self.frontmost = frontmost
    }

    /// Resolves bindings against the current keyboard layout.
    func apply(_ bindings: [AppBinding], settings: Settings) {
        var leader: [CGKeyCode: String] = [:]
        var bare: [CGKeyCode: String] = [:]

        for binding in bindings where !binding.bundleID.isEmpty {
            guard let code = KeyboardLayout.keyCode(forBinding: binding.key) else {
                log.debug("no key for '\(binding.key, privacy: .public)' on this layout")
                continue
            }

            if binding.usesLeader { leader[code] = binding.bundleID } else { bare[code] = binding.bundleID }
        }

        bindingsLock.lock()
        leaderBindings = leader
        bareBindings = bare
        leaderFlags = settings.leader.flags
        appSwitcherFlags = settings.appSwitcher.flags
        displayMove = settings.displayMoveModifier
        bindingsLock.unlock()

        log.notice("\(leader.count, privacy: .public) leader bindings, \(bare.count, privacy: .public) bare")
    }

    private func bundleID(for code: CGKeyCode, withLeader: Bool) -> String? {
        bindingsLock.lock()
        defer { bindingsLock.unlock() }

        return withLeader ? leaderBindings[code] : bareBindings[code]
    }

    private var hotkeys: (leader: CGEventFlags, appSwitcher: CGEventFlags) {
        bindingsLock.lock()
        defer { bindingsLock.unlock() }

        return (leaderFlags, appSwitcherFlags)
    }

    // MARK: - Event handling

    func handle(type: CGEventType, event: CGEvent) -> CGEvent? {
        switch type {
        case .keyDown: return handleKeyDown(event)
        case .flagsChanged: return handleFlagsChanged(event)
        default: return event
        }
    }

    private func handleKeyDown(_ event: CGEvent) -> CGEvent? {
        let code = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = Modifiers.held(in: event)

        // Shift only reverses direction, so it comes out before matching.
        let backwards = flags.contains(.maskShift)
        let base = flags.subtracting(.maskShift)
        let step = backwards ? -1 : 1
        let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        let (leader, appSwitcher) = hotkeys

        if code == CGKeyCode(kVK_Tab) {
            if base == leader {
                // Repeats are ignored but still swallowed, or the Dock answers them.
                if !isRepeat { openAllWindows(step: step) }
                return nil
            }

            if base == appSwitcher {
                if !isRepeat { openFrontmostAppWindows(step: step) }
                return nil
            }

            return event
        }

        // Only taken while the overlay is up, so they work normally elsewhere.
        if isOverlayVisible, let action = navigation(for: code) {
            action()
            return nil
        }

        // Against the flags as pressed, not `base`: shift is part of a window
        // binding, where the switcher only reads it as "backwards".
        bindingsLock.lock()
        let displayMoveModifier = displayMove
        bindingsLock.unlock()

        if let arrangement = WindowArrangement.matching(
            keyCode: code, modifiers: flags, displayMove: displayMoveModifier
        ) {
            if !isRepeat { onMain { $0.arrangeWindow(arrangement) } }
            return nil
        }

        if base == leader, let bundleID = bundleID(for: code, withLeader: true) {
            if !isRepeat { reach(bundleID) }
            return nil
        }

        if base.isEmpty, let bundleID = bundleID(for: code, withLeader: false) {
            if !isRepeat { onMain { $0.reachApplication(bundleID) } }
            return nil
        }

        return event
    }

    /// Never swallowed: other applications need modifier changes too.
    private func handleFlagsChanged(_ event: CGEvent) -> CGEvent? {
        guard isOverlayVisible, !Modifiers.anyHeld(in: event) else { return event }

        isOverlayVisible = false
        onMain { $0.commit() }

        return event
    }

    // MARK: - Actions

    private func navigation(for code: CGKeyCode) -> (() -> Void)? {
        switch Int(code) {
        case kVK_Escape:
            return { [self] in
                isOverlayVisible = false
                onMain { $0.cancel() }
            }
        case kVK_RightArrow: return { [self] in onMain { $0.move(by: 1) } }
        case kVK_LeftArrow: return { [self] in onMain { $0.move(by: -1) } }
        case kVK_DownArrow: return { [self] in onMain { $0.moveRow(by: 1) } }
        case kVK_UpArrow: return { [self] in onMain { $0.moveRow(by: -1) } }
        default: return nil
        }
    }

    private func openAllWindows(step: Int) {
        isOverlayVisible = true
        onMain { $0.showAllWindows(step: step) }
    }

    private func openFrontmostAppWindows(step: Int) {
        isOverlayVisible = true
        onMain { $0.showFrontmostAppWindows(step: step) }
    }

    /// Overlay open: narrow to this app. App already in front: walk its windows.
    /// Otherwise: switch to it.
    private func reach(_ bundleID: String) {
        if isOverlayVisible {
            onMain { $0.showWindows(of: bundleID, step: 1) }
            return
        }

        if frontmost.bundleID == bundleID {
            isOverlayVisible = true
            onMain { $0.showWindows(of: bundleID, step: 1) }
            return
        }

        onMain { $0.reachApplication(bundleID) }
    }

    /// The decision is already made; only the effect crosses to main.
    private func onMain(_ body: @escaping @MainActor (SwitcherPresenting) -> Void) {
        let presenter = presenter
        DispatchQueue.main.async {
            MainActor.assumeIsolated { body(presenter) }
        }
    }
}
