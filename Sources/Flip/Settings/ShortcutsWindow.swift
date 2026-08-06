import AppKit
import SwiftUI

/// The shortcuts window, built once and kept.
///
/// An accessory application has no Dock icon and is never the active application,
/// so ordering a window front is not enough to make it visible — it would open
/// behind whatever the user is looking at. Activating explicitly is what brings
/// both the app and the window forward.
@MainActor
final class ShortcutsWindow {
    private let store: BindingStore
    private var window: NSWindow?

    init(store: BindingStore) {
        self.store = store
    }

    func show() {
        if window == nil { window = build() }

        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    private func build() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 380),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Flip Shortcuts"

        let host = NSHostingView(rootView: ShortcutsView(store: store))
        // Left at its default, the hosting view derives the window's size from the
        // content's ideal size — which for a list is the height of every row at
        // once. Fourteen bindings made the window 875 points tall and the scroll
        // view pointless. Emptying it hands sizing back to the window.
        host.sizingOptions = []
        window.contentView = host

        window.contentMinSize = NSSize(width: 460, height: 320)
        window.setContentSize(NSSize(width: 520, height: 420))
        window.center()

        // Closing a window normally deallocates it. Keeping it means reopening is
        // instant and the scroll position survives.
        window.isReleasedWhenClosed = false

        return window
    }
}
