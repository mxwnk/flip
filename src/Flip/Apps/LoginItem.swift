import Foundation
import OSLog
import ServiceManagement

/// Starting Flip at login. The plist ships in the bundle and is registered by the
/// app, which puts it under System Settings › Login Items and resolves
/// `BundleProgram` against the bundle, so moving Flip cannot strand it.
@MainActor
enum LoginItem {
    private static let log = Logger(subsystem: Bundle.identifier, category: "loginitem")
    private static let service = SMAppService.agent(plistName: "dev.mxwnk.Flip.login.plist")

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

    /// Deletes the old plist but does not boot the job out: this process is very
    /// likely the one it started. Without the file it is not loaded again.
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
