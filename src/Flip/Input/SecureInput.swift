import AppKit
import Carbon.HIToolbox

/// While any process holds secure event input, the window server keeps every
/// key-down from every event tap. The Dock's ⌘Tab is a system hotkey and still
/// works, so Flip looks outranked. The holder keeps it until it releases it or
/// exits, which is why logging out cures it.
struct SecureInputHolder: Equatable {
    let pid: pid_t?
    let name: String?

    /// `kCGSSessionSecureInputPID` is undocumented and measured unreliable: it
    /// follows the application in front and can name one that has quit. Fit
    /// for diagnostics, not for telling anyone what to quit.
    var description: String {
        switch (name, pid) {
        case let (name?, pid?): return "\(name) (pid \(pid))"
        case let (nil, pid?): return "pid \(pid)"
        default: return "an unknown process"
        }
    }

    static var isOn: Bool { IsSecureEventInputEnabled() }

    /// The lock screen's password field holds secure input for as long as the
    /// screen is locked, and rightly. The key is absent while unlocked.
    static var isScreenLocked: Bool {
        let session = CGSessionCopyCurrentDictionary() as? [String: Any]
        return session?["CGSSessionScreenIsLocked"] as? Bool ?? false
    }

    @MainActor
    static func current() -> SecureInputHolder? {
        guard IsSecureEventInputEnabled() else { return nil }

        let pid = sessionSecureInputPID()
        let name = pid.flatMap { NSRunningApplication(processIdentifier: $0)?.localizedName }

        return SecureInputHolder(pid: pid, name: name)
    }

    private static func sessionSecureInputPID() -> pid_t? {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any],
              let pid = session["kCGSSessionSecureInputPID"] as? Int,
              pid > 0
        else { return nil }

        return pid_t(pid)
    }
}

/// Decides when to explain. A focused password field holds secure input for
/// as long as it is focused, and rightly, so only a long stretch is worth a
/// word — and one stretch is explained once. The lock screen is such a field,
/// so the stretch is only counted from the moment the screen is unlocked.
struct SecureInputEpisode {
    static let patience: TimeInterval = 15

    enum Change: Equatable {
        case started
        case ended
        case needsExplaining
        case none
    }

    /// Where the patience is measured from: the start, or the last moment the
    /// screen was seen locked.
    private(set) var countingSince: Date?
    private var hasExplained = false

    var isOn: Bool { countingSince != nil }

    mutating func observe(isOn: Bool, isScreenLocked: Bool = false, at now: Date) -> Change {
        guard isOn else { return end() }
        guard let countingSince else { return start(at: now) }
        guard !isScreenLocked else { return restartCounting(at: now) }
        guard !hasExplained, now.timeIntervalSince(countingSince) >= Self.patience else { return .none }

        hasExplained = true
        return .needsExplaining
    }

    private mutating func start(at now: Date) -> Change {
        countingSince = now
        return .started
    }

    private mutating func restartCounting(at now: Date) -> Change {
        countingSince = now
        return .none
    }

    private mutating func end() -> Change {
        guard countingSince != nil else { return .none }

        countingSince = nil
        hasExplained = false
        return .ended
    }
}
