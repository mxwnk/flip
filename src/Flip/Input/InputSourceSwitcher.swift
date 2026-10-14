import AppKit
import OSLog

/// Puts each application's input source on whenever it comes to the front,
/// however it got there: Flip, the Dock, a click or ⌘Tab alike.
@MainActor
final class InputSourceSwitcher {
    private let config: ConfigStore
    private let log = Logger(subsystem: Bundle.identifier, category: "inputsource")
    private var observer: NSObjectProtocol?

    init(config: ConfigStore) {
        self.config = config
    }

    func start() {
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated { self?.applicationActivated(application?.bundleIdentifier) }
        }
    }

    /// Nil when nothing needs to happen: no rule, or the source is already on.
    nonisolated static func sourceToSelect(
        for bundleID: String?,
        rules: [String: String],
        current: String?
    ) -> String? {
        guard let bundleID, let wanted = rules[bundleID], wanted != current else { return nil }

        return wanted
    }

    private func applicationActivated(_ bundleID: String?) {
        guard let wanted = Self.sourceToSelect(
            for: bundleID, rules: config.settings.inputSources, current: InputSources.currentID
        ) else { return }

        guard InputSources.select(wanted) else {
            return log.error("could not switch to \(wanted, privacy: .public) for \(bundleID ?? "?", privacy: .public); is it enabled in System Settings?")
        }

        log.debug("switched to \(wanted, privacy: .public) for \(bundleID ?? "?", privacy: .public)")
    }
}
