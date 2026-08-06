import AppKit
import OSLog

@MainActor
enum AppLauncher {
    private static let log = Logger(subsystem: Bundle.identifier, category: "launcher")

    /// Brings an application to the front, starting it if it is not running.
    static func activate(_ bundleID: String) {
        if let running = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleID)
            .first
        {
            running.activate()
            return
        }

        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            log.error("no application installed for \(bundleID, privacy: .public)")
            return
        }

        NSWorkspace.shared.openApplication(at: url, configuration: .init())
    }
}
