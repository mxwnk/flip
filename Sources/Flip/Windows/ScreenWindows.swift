import CoreGraphics

/// The window server's own view of what is on screen right now.
///
/// One call, no accessibility, no privacy grant, about a millisecond — and it is
/// the only source for the two things the accessibility API cannot answer: which
/// space a window is on, and the front-to-back order.
enum ScreenWindows {
    struct Entry {
        let id: CGWindowID
        let pid: pid_t
        /// Zero is frontmost.
        let order: Int
    }

    /// Windows on the current space, front to back.
    static func onCurrentSpace() -> [Entry] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let listing = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]]
        else { return [] }

        var entries: [Entry] = []
        entries.reserveCapacity(listing.count)

        for (order, window) in listing.enumerated() {
            // Layer zero is the ordinary window layer. Everything else is the menu
            // bar, the Dock, wallpaper, notification banners and similar chrome.
            guard let layer = window[kCGWindowLayer as String] as? Int, layer == 0,
                  let id = window[kCGWindowNumber as String] as? CGWindowID,
                  let pid = window[kCGWindowOwnerPID as String] as? pid_t
            else { continue }

            entries.append(Entry(id: id, pid: pid, order: order))
        }

        return entries
    }
}
