import AppKit
import SwiftUI

/// An accessory application is never the active one, so ordering a window front
/// is not enough — it opens behind everything without an explicit activate.
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
            contentRect: NSRect(x: 0, y: 0, width: 660, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Flip Settings"

        let host = NSHostingView(rootView: SettingsView(settings: settings, bindings: bindings))
        // Otherwise the hosting view sizes the window to the content's ideal size,
        // which for a list is every row at once.
        host.sizingOptions = []
        window.contentView = host

        // A comfortable floor, not a required one: every tab is a grouped form now
        // and scrolls, so nothing can be cut off however small this gets.
        window.contentMinSize = NSSize(width: 520, height: 460)
        window.setContentSize(NSSize(width: 660, height: 620))
        window.center()

        // Remembers a size you dragged to. Without it every launch snaps back.
        window.setFrameAutosaveName("Settings")
        window.setFrameUsingName("Settings")

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

            WindowActionsView(settings: settings)
                .tabItem { Label("Windows", systemImage: "macwindow.on.rectangle") }

            ExclusionsView(settings: settings)
                .tabItem { Label("Excluded", systemImage: "eye.slash") }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
