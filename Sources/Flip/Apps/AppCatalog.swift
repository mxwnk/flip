import AppKit

/// Names and icons for bundle identifiers, looked up once each.
///
/// Resolving either one means hitting Launch Services and the file system. Cheap,
/// but the same handful of applications comes up every time the switcher opens.
@MainActor
enum AppCatalog {
    private static var icons: [String: NSImage] = [:]
    private static var names: [String: String] = [:]

    static func icon(for bundleID: String?) -> NSImage? {
        guard let bundleID, !bundleID.isEmpty else { return nil }
        if let cached = icons[bundleID] { return cached }
        guard let url = url(for: bundleID) else { return nil }

        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icons[bundleID] = icon

        return icon
    }

    /// Falls back to the identifier itself, which is the honest answer when the
    /// application is not installed — a binding carried over from another machine.
    static func name(for bundleID: String) -> String {
        if let cached = names[bundleID] { return cached }
        guard let url = url(for: bundleID) else { return bundleID }

        let name = FileManager.default.displayName(atPath: url.path)
        names[bundleID] = name

        return name
    }

    static func isInstalled(_ bundleID: String) -> Bool {
        !bundleID.isEmpty && url(for: bundleID) != nil
    }

    private static func url(for bundleID: String) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }

    /// Everything with a Dock icon right now, for the quick path in the picker.
    /// Flip itself is an agent and so is absent, which is what we want.
    static func running() -> [(bundleID: String, name: String)] {
        var seen = Set<String>()

        return NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { application -> (String, String)? in
                guard let bundleID = application.bundleIdentifier, seen.insert(bundleID).inserted
                else { return nil }

                return (bundleID, application.localizedName ?? bundleID)
            }
            .sorted { $0.1.localizedStandardCompare($1.1) == .orderedAscending }
    }
}
