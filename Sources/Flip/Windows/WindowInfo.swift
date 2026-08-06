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

    /// Higher is more recent. macOS exposes no per-window focus history.
    var focusOrder: UInt64
}
