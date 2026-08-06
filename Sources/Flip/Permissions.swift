import ApplicationServices
import CoreGraphics
import OSLog

/// The two privacy grants Flip depends on. Both are keyed by code signature, so
/// they only survive a rebuild while the app keeps a stable signing identity —
/// see the `cert` target in the Makefile.
enum Permissions {
    private static let log = Logger(subsystem: Bundle.identifier, category: "permissions")

    /// Required for everything: reading window lists and installing the event tap
    /// both fail without it, the latter silently.
    static func hasAccessibility(prompting: Bool = false) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String

        return AXIsProcessTrustedWithOptions([key: prompting] as CFDictionary)
    }

    /// Only window thumbnails need this. Without it the switcher still works and
    /// falls back to application icons.
    static func hasScreenRecording(requesting: Bool = false) -> Bool {
        if CGPreflightScreenCaptureAccess() { return true }

        return requesting ? CGRequestScreenCaptureAccess() : false
    }

    struct Status: Equatable {
        var accessibility: Bool
        var screenRecording: Bool

        var isComplete: Bool { accessibility && screenRecording }
    }

    /// Asking is what puts the app into the System Settings lists in the first
    /// place, so this runs even when a grant is already in hand.
    static func request() -> Status {
        Status(
            accessibility: hasAccessibility(prompting: true),
            screenRecording: hasScreenRecording(requesting: true)
        )
    }

    static func current() -> Status {
        Status(accessibility: hasAccessibility(), screenRecording: hasScreenRecording())
    }

    static func report(_ status: Status) {
        let mark = { (granted: Bool) in granted ? "granted" : "MISSING" }

        log.notice("accessibility: \(mark(status.accessibility), privacy: .public)")
        log.notice("screen recording: \(mark(status.screenRecording), privacy: .public)")

        // Direct runs from a terminal also want to see this, and stdout is the
        // only place they will look.
        print("accessibility:    \(mark(status.accessibility))")
        print("screen recording: \(mark(status.screenRecording))")
    }
}
