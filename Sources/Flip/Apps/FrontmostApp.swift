import AppKit
import Foundation

/// The frontmost application's bundle identifier, kept current by a workspace
/// notification rather than asked for on demand.
///
/// The key router needs it to decide whether Alt-S should switch to Spotify or
/// start walking Spotify's windows, and it decides that on the event tap's thread
/// — where an AppKit call has no business being.
///
/// Unchecked rather than actually Sendable: written on the main thread and read
/// from the tap thread, with the only mutable state guarded by the lock below.
final class FrontmostApp: @unchecked Sendable {
    private let lock = NSLock()
    private var cached: String?

    var bundleID: String? {
        lock.lock()
        defer { lock.unlock() }

        return cached
    }

    @MainActor
    func startObserving() {
        update(to: NSWorkspace.shared.frontmostApplication)

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let key = NSWorkspace.applicationUserInfoKey
            self?.update(to: notification.userInfo?[key] as? NSRunningApplication)
        }
    }

    private func update(to application: NSRunningApplication?) {
        lock.lock()
        cached = application?.bundleIdentifier
        lock.unlock()
    }
}
