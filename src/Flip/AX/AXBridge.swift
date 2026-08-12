import ApplicationServices
import CAXShim
import CoreGraphics

enum AXBridge {
    /// The WindowServer's ID, which matches an AX window against
    /// CGWindowListCopyWindowInfo for z-order and space membership.
    static func windowID(of element: AXUIElement) -> CGWindowID? {
        var id: CGWindowID = 0
        guard FlipReadWindowID(element, &id) == .success else { return nil }

        return id
    }

    /// The default is six seconds; a short one turns a hung app into a missing
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

    /// Native full screen — the green button, its own space. Not in the SDK,
    /// but the attribute is real and writing false leaves it.
    static let fullScreenAttribute = "AXFullScreen"

    static func setBool(_ value: Bool, _ attribute: String, of element: AXUIElement) {
        AXUIElementSetAttributeValue(
            element, attribute as CFString, value ? kCFBooleanTrue : kCFBooleanFalse
        )
    }

    static func frame(of element: AXUIElement) -> CGRect? {
        guard let origin = point(kAXPositionAttribute as String, of: element),
              let size = size(kAXSizeAttribute as String, of: element)
        else { return nil }

        return CGRect(origin: origin, size: size)
    }

    /// Position, size, position again: a window moved to a display it does not
    /// fit on gets clamped, and the second pass corrects that.
    static func setFrame(_ frame: CGRect, of element: AXUIElement) {
        setPosition(frame.origin, of: element)
        setSize(frame.size, of: element)
        setPosition(frame.origin, of: element)
    }

    private static func point(_ attribute: String, of element: AXUIElement) -> CGPoint? {
        guard let raw = value(attribute, of: element), CFGetTypeID(raw) == AXValueGetTypeID()
        else { return nil }

        var point = CGPoint.zero
        guard AXValueGetValue(raw as! AXValue, .cgPoint, &point) else { return nil }

        return point
    }

    private static func size(_ attribute: String, of element: AXUIElement) -> CGSize? {
        guard let raw = value(attribute, of: element), CFGetTypeID(raw) == AXValueGetTypeID()
        else { return nil }

        var size = CGSize.zero
        guard AXValueGetValue(raw as! AXValue, .cgSize, &size) else { return nil }

        return size
    }

    private static func setPosition(_ point: CGPoint, of element: AXUIElement) {
        var point = point
        guard let wrapped = AXValueCreate(.cgPoint, &point) else { return }

        AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, wrapped)
    }

    private static func setSize(_ size: CGSize, of element: AXUIElement) {
        var size = size
        guard let wrapped = AXValueCreate(.cgSize, &size) else { return }

        AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, wrapped)
    }

    /// Panels, sheets and popovers carry a different subrole.
    static func isStandardWindow(_ element: AXUIElement) -> Bool {
        string(kAXSubroleAttribute as String, of: element) == (kAXStandardWindowSubrole as String)
    }
}
