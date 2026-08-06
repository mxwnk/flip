import Foundation
import OSLog
import ServiceManagement

/// Starting Flip at login.
///
/// The agent's plist ships inside the app bundle and is registered by the app
/// itself, rather than written into ~/Library/LaunchAgents by the Makefile. That
/// puts it under System Settings › Login Items where it can be found and switched
/// off, and `BundleProgram` is resolved against the bundle, so moving Flip does
/// not leave a launch agent pointing at nothing.
@MainActor
enum LoginItem {
    private static let log = Logger(subsystem: Bundle.identifier, category: "loginitem")
    private static let service = SMAppService.agent(plistName: "dev.mxwnk.Flip.login.plist")

    /// The plist the Makefile used to write. Left over on machines set up before
    /// the switch, and it would start a second copy at every login.
    private static let legacyAgent = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent("Library/LaunchAgents/dev.mxwnk.Flip.plist")

    static var isEnabled: Bool {
        service.status == .enabled
    }

    /// True when the user switched Flip off in System Settings. Registering again
    /// from here will not override that, and pretending otherwise would make the
    /// toggle lie.
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

    /// Removes the old launch agent's plist, but deliberately does not boot the job
    /// out: this process is very likely the one it started, and booting it out
    /// would kill us mid-migration. Deleting the file is enough — it simply will
    /// not be loaded again at the next login.
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
