import AppKit

/// Application icons, looked up once per bundle.
///
/// Resolving an icon means hitting Launch Services and the file system, which is
/// cheap but not free, and the same handful of applications comes up every time
/// the switcher opens.
@MainActor
enum AppIconCache {
    private static var icons: [String: NSImage] = [:]

    static func icon(for bundleID: String?) -> NSImage? {
        guard let bundleID else { return nil }
        if let cached = icons[bundleID] { return cached }

        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        else { return nil }

        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icons[bundleID] = icon

        return icon
    }
}
