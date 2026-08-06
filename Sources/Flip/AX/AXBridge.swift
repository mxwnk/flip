import ApplicationServices
import CAXShim
import CoreGraphics

enum AXBridge {
    /// The WindowServer's ID for an accessibility element, or nil if the element
    /// is not a window. This is what lets an AX window be matched against
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

    // MARK: - Attributes
    //
    // Every one of these is a synchronous round trip into another process, so they
    // belong on the window store's thread and nowhere near the main one.

    static func value(_ attribute: String, of element: AXUIElement) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success
        else { return nil }

        return value
    }

    static func string(_ attribute: String, of element: AXUIElement) -> String? {
        value(attribute, of: element) as? String
    }

    static func bool(_ attribute: String, of element: AXUIElement) -> Bool? {
        value(attribute, of: element) as? Bool
    }

    static func elements(_ attribute: String, of element: AXUIElement) -> [AXUIElement] {
        value(attribute, of: element) as? [AXUIElement] ?? []
    }

    static func element(_ attribute: String, of element: AXUIElement) -> AXUIElement? {
        guard let raw = value(attribute, of: element), CFGetTypeID(raw) == AXUIElementGetTypeID()
        else { return nil }

        return (raw as! AXUIElement)
    }

    /// Ordinary windows only. Panels, sheets, popovers and the Dock's own windows
    /// all carry a different subrole and have no business in a switcher.
    static func isStandardWindow(_ element: AXUIElement) -> Bool {
        string(kAXSubroleAttribute as String, of: element) == (kAXStandardWindowSubrole as String)
    }
}
