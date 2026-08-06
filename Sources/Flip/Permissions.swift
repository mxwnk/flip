import ApplicationServices
import CoreGraphics
import OSLog

/// The two privacy grants Flip depends on. Both are keyed by code signature, so
/// they only survive a rebuild while the signing identity is stable.
enum Permissions {
    private static let log = Logger(subsystem: Bundle.identifier, category: "permissions")

    /// Required for everything; the event tap fails silently without it.
    static func hasAccessibility(prompting: Bool = false) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String

        return AXIsProcessTrustedWithOptions([key: prompting] as CFDictionary)
    }

    /// Thumbnails only; without it the tiles fall back to application icons.
    static func hasScreenRecording(requesting: Bool = false) -> Bool {
        if CGPreflightScreenCaptureAccess() { return true }

        return requesting ? CGRequestScreenCaptureAccess() : false
    }

    struct Status: Equatable {
        var accessibility: Bool
        var screenRecording: Bool

        var isComplete: Bool { accessibility && screenRecording }
    }

    /// Asking is what puts the app into the System Settings lists at all.
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

        print("accessibility:    \(mark(status.accessibility))")
        print("screen recording: \(mark(status.screenRecording))")
    }
}
