import ApplicationServices
import CAXShim
import CoreGraphics

enum AXBridge {
    /// The WindowServer's ID for an accessibility element, or nil if the element
    /// is not a window. This is what later lets an AX window be matched against
    /// CGWindowListCopyWindowInfo for z-order and space membership.
    static func windowID(of element: AXUIElement) -> CGWindowID? {
        var id: CGWindowID = 0
        guard _AXUIElementGetWindow(element, &id) == .success else { return nil }

        return id
    }

    /// An AX call to a busy application blocks the calling thread until the app
    /// answers, and the default timeout is six seconds. Every application element
    /// gets a short one, so a hung app degrades into a missing window rather than
    /// a frozen switcher.
    static func limitMessagingTimeout(of application: AXUIElement, to seconds: Float = 0.5) {
        AXUIElementSetMessagingTimeout(application, seconds)
    }
}
