import AppKit
import OSLog

/// Everything worth knowing when Flip misbehaves, as plain text on the clipboard.
/// The point is that a report can be written without opening a terminal, so this
/// gathers what someone would otherwise be talked through collecting.
@MainActor
enum Diagnostics {
    static func report(
        status: Permissions.Status,
        isPaused: Bool,
        settings: Settings,
        bindingCount: Int,
        windowCount: Int
    ) -> String {
        var lines: [String] = []

        lines.append("Flip \(Bundle.main.versionDescription)")
        // Which copy is running matters: a Homebrew install and a `make run` build
        // both answer to the same name, and only the path tells them apart.
        lines.append("Bundle: \(Bundle.main.bundlePath)")
        lines.append("macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)")
        lines.append("")

        lines.append("Accessibility: \(status.accessibility ? "granted" : "MISSING")")
        lines.append("Screen Recording: \(status.screenRecording ? "granted" : "MISSING")")
        lines.append("Start at login: \(LoginItem.isEnabled ? "on" : "off")")
        lines.append("Event tap: \(isPaused ? "paused" : "running")")
        lines.append("")

        lines.append("Switch windows with: \(settings.leader.label)")
        lines.append("Switch within an application with: \(settings.appSwitcher.label)")
        lines.append("Overlay delay: \(settings.overlayDelay.label)")
        lines.append("Thumbnails: \(settings.showThumbnails ? "on" : "off")")
        lines.append("Shortcuts: \(bindingCount)")
        lines.append("Excluded applications: \(settings.excludedBundleIDs.count)")
        lines.append("Windows tracked: \(windowCount)")
        lines.append("")

        lines.append("Recent log:")
        let recent = recentLog()
        lines.append(contentsOf: recent.isEmpty ? ["  (none)"] : recent.map { "  \($0)" })

        return lines.joined(separator: "\n")
    }

    static func copyToPasteboard(_ report: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(report, forType: .string)
    }

    /// Flip's own entries only. `OSLogStore.local()` would need an entitlement
    /// Flip has no business holding; the current process needs none.
    private static func recentLog(limit: Int = 60) -> [String] {
        guard let store = try? OSLogStore(scope: .currentProcessIdentifier) else { return [] }

        let since = store.position(date: Date().addingTimeInterval(-600))
        let predicate = NSPredicate(format: "subsystem == %@", Bundle.identifier)
        guard let entries = try? store.getEntries(at: since, matching: predicate) else { return [] }

        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"

        return entries
            .compactMap { $0 as? OSLogEntryLog }
            .suffix(limit)
            .map { "\(formatter.string(from: $0.date)) [\($0.category)] \($0.composedMessage)" }
    }
}
