import AppKit
import SwiftUI

/// The settings window, built once and kept.
///
/// An accessory application has no Dock icon and is never the active application,
/// so ordering a window front is not enough to make it visible — it would open
/// behind whatever the user is looking at. Activating explicitly is what brings
/// both the app and the window forward.
@MainActor
final class SettingsWindow {
    private let settings: SettingsStore
    private let bindings: BindingStore
    private var window: NSWindow?

    init(settings: SettingsStore, bindings: BindingStore) {
        self.settings = settings
        self.bindings = bindings
    }

    func show() {
        if window == nil { window = build() }

        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    private func build() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 440),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Flip Settings"

        let host = NSHostingView(rootView: SettingsView(settings: settings, bindings: bindings))
        // Left at its default, the hosting view derives the window's size from the
        // content's ideal size — which for a list is the height of every row at
        // once. Emptying it hands sizing back to the window.
        host.sizingOptions = []
        window.contentView = host

        window.contentMinSize = NSSize(width: 500, height: 360)
        window.setContentSize(NSSize(width: 560, height: 440))
        window.center()

        // Closing a window normally deallocates it. Keeping it means reopening is
        // instant and the selected tab survives.
        window.isReleasedWhenClosed = false

        return window
    }
}

private struct SettingsView: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var bindings: BindingStore

    var body: some View {
        TabView {
            GeneralView(settings: settings)
                .tabItem { Label("General", systemImage: "gearshape") }

            ShortcutsView(store: bindings)
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }

            ExclusionsView(settings: settings)
                .tabItem { Label("Excluded", systemImage: "eye.slash") }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
