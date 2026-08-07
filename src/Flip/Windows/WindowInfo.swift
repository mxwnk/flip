import ApplicationServices
import CoreGraphics

/// One switchable window, as a plain copy. Nothing here is read back through the
/// accessibility API when the switcher opens.
struct WindowInfo: Identifiable {
    let id: CGWindowID
    let element: AXUIElement
    let pid: pid_t
    let bundleID: String?
    let applicationName: String
    var title: String
    var isMinimized: Bool

    /// As accessibility reports it, which is not what the window server reports
    /// once Stage Manager has parked the window — see `ThumbnailStore`.
    var frame: CGRect

    /// Higher is more recent. macOS exposes no per-window focus history.
    var focusOrder: UInt64
}
