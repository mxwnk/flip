import AppKit
import Foundation

/// Cached, because the router reads it on the tap thread where an AppKit call
/// has no business being. Written on main, guarded by the lock below.
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
