import ApplicationServices
import CAXShim
import CoreGraphics

enum AXBridge {
    /// The WindowServer's ID, which is what matches an AX window against
    /// CGWindowListCopyWindowInfo for z-order and space membership.
    static func windowID(of element: AXUIElement) -> CGWindowID? {
        var id: CGWindowID = 0
        guard _AXUIElementGetWindow(element, &id) == .success else { return nil }

        return id
    }

    /// The default is six seconds. A short one turns a hung app into a missing
    /// window rather than a frozen switcher.
    static func limitMessagingTimeout(of application: AXUIElement, to seconds: Float = 0.5) {
        AXUIElementSetMessagingTimeout(application, seconds)
    }

    // MARK: - Attributes
    //
    // Each is a synchronous round trip into another process.

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

    /// Panels, sheets and popovers carry a different subrole.
    static func isStandardWindow(_ element: AXUIElement) -> Bool {
        string(kAXSubroleAttribute as String, of: element) == (kAXStandardWindowSubrole as String)
    }
}
