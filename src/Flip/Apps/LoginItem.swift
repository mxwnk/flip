import Foundation
import OSLog
import ServiceManagement

/// Starting Flip at login. The plist ships in the bundle, so it appears under
/// System Settings › Login Items and moving Flip cannot strand it.
@MainActor
enum LoginItem {
    private static let log = Logger(subsystem: Bundle.identifier, category: "loginitem")
    /// Built from the identifier rather than typed out: the Makefile names the
    /// file after `BUNDLE_ID` and writes the same value into Info.plist, so
    /// deriving it here ties both sides to one source. Spelled out, the two
    /// agreed only by maintenance — and a mismatch shows up as a `register()`
    /// that throws at runtime and nowhere else.
    private static let service = SMAppService
        .agent(plistName: "\(Bundle.identifier).login.plist")

    /// Written by the Makefile before the switch; would start a second copy.
    private static let legacyAgent = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent("Library/LaunchAgents/dev.mxwnk.Flip.plist")

    static var isEnabled: Bool {
        service.status == .enabled
    }

    /// Switched off in System Settings. Registering again will not override it.
    static var isBlockedBySystemSettings: Bool {
        service.status == .requiresApproval
    }

    static func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }
            log.notice("login item \(enabled ? "registered" : "unregistered", privacy: .public)")
        } catch {
            log.error("login item change failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Deletes the plist without booting the job out — this process is probably
    /// the one it started. Without the file it never loads again.
    static func migrateFromLegacyAgent() {
        guard FileManager.default.fileExists(atPath: legacyAgent.path) else { return }

        do {
            try FileManager.default.removeItem(at: legacyAgent)
            log.notice("removed the legacy launch agent; registering the bundled one")
            setEnabled(true)
        } catch {
            log.error("could not remove the legacy agent: \(error.localizedDescription, privacy: .public)")
        }
    }
}
