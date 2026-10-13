import AppKit
import Carbon.HIToolbox

/// While any process holds secure event input, the window server keeps every
/// key-down from every event tap. The Dock's ⌘Tab is a system hotkey and still
/// works, so Flip looks outranked. The holder keeps it until it releases it or
/// exits, which is why logging out cures it.
struct SecureInputHolder: Equatable {
    let pid: pid_t?
    let name: String?

    /// `kCGSSessionSecureInputPID` is undocumented, so the holder may be unknown.
    var description: String {
        switch (name, pid) {
        case let (name?, pid?): return "\(name) (pid \(pid))"
        case let (nil, pid?): return "pid \(pid)"
        default: return "an unknown process"
        }
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
