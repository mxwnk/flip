import ApplicationServices
import CoreGraphics

/// One switchable window, as a plain copy.
///
/// Nothing here is read back through the accessibility API when the switcher opens
/// — avoiding exactly that is the reason the store exists. The values are kept
/// current by notifications instead.
struct WindowInfo: Identifiable {
    let id: CGWindowID
    let element: AXUIElement
    let pid: pid_t
    let bundleID: String?
    let applicationName: String
    var title: String
    var isMinimized: Bool

    /// Monotonic; higher means more recently focused. Maintained here rather than
    /// asked of the system, because macOS exposes no per-window focus history.
    var focusOrder: UInt64
}
