import CoreGraphics

/// The window server's view of what is on screen: one call, ~1 ms, no privacy
/// grant. The only source for space membership and front-to-back order.
enum ScreenWindows {
    struct Entry {
        let id: CGWindowID
        let pid: pid_t
        /// Zero is frontmost.
        let order: Int
    }

    static func onCurrentSpace() -> [Entry] {
        entries(matching: [.optionOnScreenOnly, .excludeDesktopElements])
    }

    /// Every space, which the window server only reports without
    /// `optionOnScreenOnly`. Far noisier — helper panels and untitled service
    /// windows come with it — but it is only ever intersected with the
    /// accessibility model, so a superset is exactly what is wanted: it says
    /// which of Flip's windows still exist, not which ones to show.
    ///
    /// The order is meaningless here. Only one space has a front to back order.
    static func everySpace() -> [Entry] {
        entries(matching: [.excludeDesktopElements])
    }

    private static func entries(matching options: CGWindowListOption) -> [Entry] {
        guard let listing = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]]
        else { return [] }

        var entries: [Entry] = []
        entries.reserveCapacity(listing.count)

        for (order, window) in listing.enumerated() {
            // Layer zero is ordinary windows; the rest is menu bar, Dock, chrome.
            guard let layer = window[kCGWindowLayer as String] as? Int, layer == 0,
                  let id = window[kCGWindowNumber as String] as? CGWindowID,
                  let pid = window[kCGWindowOwnerPID as String] as? pid_t
            else { continue }

            entries.append(Entry(id: id, pid: pid, order: order))
        }

        return entries
    }
}
