import Carbon.HIToolbox
import CoreGraphics
import Foundation
import OSLog

/// Turns raw key events into switcher commands.
///
/// Alt is a leader key: it opens the switcher, holds it open while the selection
/// moves, and releasing it commits. That is why none of this can be built on
/// registered hotkeys — the event that ends the interaction is a modifier coming
/// back up, which no hotkey API reports.
///
/// Everything here runs on the event tap's thread, and every decision is made
/// synchronously: whether to swallow an event cannot wait for the main thread.
/// The resulting work is what gets handed over.
final class KeyRouter {
    private let presenter: SwitcherPresenting
    private let frontmost: FrontmostApp
    private let log = Logger(subsystem: Bundle.identifier, category: "router")

    /// Read and written on the tap thread for every swallow decision, and cleared
    /// from the main thread when the overlay closes without being asked to. An
    /// uncontended lock costs nothing next to being wrong about this: a router
    /// that thinks a closed overlay is open swallows arrow keys system-wide.
    private let visibility = NSLock()
    private var overlayIsVisible = false

    private var isOverlayVisible: Bool {
        get { visibility.lock(); defer { visibility.unlock() }; return overlayIsVisible }
        set { visibility.lock(); overlayIsVisible = newValue; visibility.unlock() }
    }

    /// Called when the overlay closed on its own — its safety timeout expired, or
    /// there were no windows to show in the first place.
    func overlayDidClose() {
        isOverlayVisible = false
    }

    /// Written on the main thread whenever the bindings or the keyboard layout
    /// change, read on the tap thread for every keystroke. It was previously
    /// neither — a plain dictionary handed between two threads — which happened to
    /// work only because layout changes are rare.
    private let bindingsLock = NSLock()
    private var leaderBindings: [CGKeyCode: String] = [:]
    private var bareBindings: [CGKeyCode: String] = [:]
    private var leaderFlags: CGEventFlags = ModifierChoice.option.flags
    private var appSwitcherFlags: CGEventFlags = ModifierChoice.command.flags

    init(presenter: SwitcherPresenting, frontmost: FrontmostApp) {
        self.presenter = presenter
        self.frontmost = frontmost
    }

    /// Resolves the configured bindings against the current keyboard layout.
    func apply(_ bindings: [AppBinding], settings: Settings) {
        var leader: [CGKeyCode: String] = [:]
        var bare: [CGKeyCode: String] = [:]

        for binding in bindings where !binding.bundleID.isEmpty {
            guard let code = KeyboardLayout.keyCode(forBinding: binding.key) else {
                // Ordinary while a row is being typed into, and worth knowing about
                // otherwise: a binding written for a layout you no longer use.
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

        // Shift only ever reverses direction, so it is taken out before the
        // modifier combination is matched.
        let backwards = flags.contains(.maskShift)
        let base = flags.subtracting(.maskShift)
        let step = backwards ? -1 : 1
        let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        let (leader, appSwitcher) = hotkeys

        if code == CGKeyCode(kVK_Tab) {
            if base == leader {
                // Holding tab should not race through the list at the key repeat
                // rate, but the event still has to be swallowed either way or the
                // Dock's own switcher answers it.
                if !isRepeat { openAllWindows(step: step) }
                return nil
            }

            if base == appSwitcher {
                if !isRepeat { openFrontmostAppWindows(step: step) }
                return nil
            }

            return event
        }

        // Arrows and Escape are only taken while the overlay is up, so they keep
        // working normally everywhere else.
        if isOverlayVisible, let action = navigation(for: code) {
            action()
            return nil
        }

        if base == leader, let bundleID = bundleID(for: code, withLeader: true) {
            if !isRepeat { reach(bundleID) }
            return nil
        }

        if base.isEmpty, let bundleID = bundleID(for: code, withLeader: false) {
            if !isRepeat { onMain { _ in AppLauncher.activate(bundleID) } }
            return nil
        }

        return event
    }

    /// Never swallowed: other applications need to see modifier changes too.
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

    /// One key, three meanings, depending on what is already happening:
    ///
    /// - overlay open, so the leader is genuinely held: narrow it to this app
    /// - the app is already in front: start walking its windows
    /// - otherwise: switch to it, which is the plain tap of Alt-S
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

        onMain { _ in AppLauncher.activate(bundleID) }
    }

    /// The decision has already been made on the tap thread; only the effect is
    /// handed to the main thread, where AppKit belongs.
    private func onMain(_ body: @escaping @MainActor (SwitcherPresenting) -> Void) {
        let presenter = presenter
        DispatchQueue.main.async {
            MainActor.assumeIsolated { body(presenter) }
        }
    }
}
