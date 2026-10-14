import AppKit
import OSLog

/// Everything worth knowing when Flip misbehaves, as plain text — so a report
/// can be written without opening a terminal.
@MainActor
enum Diagnostics {
    /// Shown in a window that scrolls, so it can afford more than a paste would.
    static let logWindow: TimeInterval = 30 * 60
    static let logLineLimit = 300

    static func report(
        status: Permissions.Status,
        isPaused: Bool,
        settings: Settings,
        bindingCount: Int,
        canReadWindowIDs: Bool,
        secureInputHolder: SecureInputHolder?,
        windowCount: Int
    ) -> DiagnosticsReport {
        typealias Fact = DiagnosticsReport.Fact

        let installation = [
            // A Homebrew install and a `make run` build answer to the same name;
            // only the path tells them apart.
            Fact(label: "Bundle", value: Bundle.main.bundlePath),
            Fact(label: "macOS", value: ProcessInfo.processInfo.operatingSystemVersionString),
        ]
        let health = [
            Fact(label: "Accessibility", value: status.accessibility ? "granted" : "MISSING"),
            Fact(label: "Screen Recording", value: status.screenRecording ? "granted" : "MISSING"),
            Fact(label: "Start at login", value: LoginItem.isEnabled ? "on" : "off"),
            Fact(label: "Event tap", value: isPaused ? "paused" : "running"),
            Fact(label: "Secure input", value: secureInputHolder.map { "ON, macOS attributes it to \($0.description)" } ?? "off"),
            Fact(label: "Window ids", value: canReadWindowIDs ? "available" : "UNSUPPORTED ON THIS SYSTEM"),
        ]
        let configuration = [
            Fact(label: "Switcher key", value: settings.switcher.leader.label),
            Fact(label: "App switcher key", value: settings.switcher.applicationLeader.label),
            Fact(label: "Overlay delay", value: settings.switcher.overlayDelay.label),
            Fact(label: "Thumbnails", value: settings.switcher.showThumbnails ? "on" : "off"),
            Fact(label: "Shortcuts", value: "\(bindingCount)"),
            Fact(label: "Excluded apps", value: "\(settings.excluded.count)"),
            Fact(label: "Windows tracked", value: "\(windowCount)"),
        ]

        return DiagnosticsReport(
            title: "Flip \(Bundle.main.versionDescription)",
            sections: [installation, health, configuration],
            log: recentLog()
        )
    }

    static func copyToPasteboard(_ report: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(report, forType: .string)
    }

    /// Flip's own entries only: `OSLogStore.local()` needs an entitlement Flip
    /// has no business holding.
    private static func recentLog() -> [DiagnosticsReport.LogLine] {
        guard let store = try? OSLogStore(scope: .currentProcessIdentifier) else { return [] }

        let since = store.position(date: Date().addingTimeInterval(-logWindow))
        let predicate = NSPredicate(format: "subsystem == %@", Bundle.identifier)
        guard let entries = try? store.getEntries(at: since, matching: predicate) else { return [] }

        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"

        return entries
            .compactMap { $0 as? OSLogEntryLog }
            .suffix(logLineLimit)
            .map { entry in
                DiagnosticsReport.LogLine(
                    time: formatter.string(from: entry.date),
                    isError: entry.level == .error || entry.level == .fault,
                    category: entry.category,
                    message: entry.composedMessage
                )
            }
    }
}
