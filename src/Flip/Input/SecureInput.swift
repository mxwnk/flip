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
/// word — and one stretch is explained once.
struct SecureInputEpisode {
    static let patience: TimeInterval = 15

    enum Change: Equatable {
        case started
        case ended
        case needsExplaining
        case none
    }

    private(set) var startedAt: Date?
    private var hasExplained = false

    var isOn: Bool { startedAt != nil }

    mutating func observe(isOn: Bool, at now: Date) -> Change {
        guard isOn else { return end() }
        guard let startedAt else { return start(at: now) }
        guard !hasExplained, now.timeIntervalSince(startedAt) >= Self.patience else { return .none }

        hasExplained = true
        return .needsExplaining
    }

    private mutating func start(at now: Date) -> Change {
        startedAt = now
        return .started
    }

    private mutating func end() -> Change {
        guard startedAt != nil else { return .none }

        startedAt = nil
        hasExplained = false
        return .ended
    }
}
