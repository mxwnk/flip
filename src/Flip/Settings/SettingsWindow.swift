import AppKit
import Carbon.HIToolbox
import CoreGraphics
import SwiftUI

/// An accessory application is never the active one, so ordering a window front
/// is not enough on its own.
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
        // Otherwise the hosting view sizes to the content's ideal size, which
        // for a list is every row at once.
        host.sizingOptions = []
        window.contentView = host

        // A comfortable floor, not a required one: every tab scrolls.
        window.contentMinSize = NSSize(width: 560, height: 640)
        window.setContentSize(NSSize(width: 680, height: 820))
        window.center()

        // Remembers a size you dragged to; without it every launch snaps back.
        window.setFrameAutosaveName("Settings")
        window.setFrameUsingName("Settings")

        // An accessory application cannot reliably be made active, so without
        // this the window opens behind whatever is in front and the menu item
        // looks dead. Well below the overlay, which still draws over it.
        window.level = .floating

        window.isReleasedWhenClosed = false

        return window
    }
}

private struct SettingsView: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var bindings: BindingStore

    @State private var tab: Tab = .general

    private enum Tab: Hashable { case general, shortcuts, windows, excluded }

    /// What the keyboard lights up, per tab. All bindings at once would be half
    /// the keys lit and no meaning.
    private var litKeys: Set<CGKeyCode> {
        switch tab {
        case .general:
            return [CGKeyCode(kVK_Tab)]
        case .shortcuts:
            return Set(bindings.bindings.compactMap { KeyboardLayout.keyCode(forBinding: $0.key) })
        case .windows:
            return Set(
                WindowArrangement.shortcuts(displayMove: settings.settings.displayMoveModifier)
                    .map(\.keyCode)
            )
        case .excluded:
            return []
        }
    }

    private var litModifiers: CGEventFlags {
        switch tab {
        case .general:
            return settings.settings.leader.flags.union(settings.settings.appSwitcher.flags)
        case .shortcuts:
            return settings.settings.leader.flags
        case .windows:
            return CGEventFlags([.maskControl, .maskAlternate])
                .union(settings.settings.displayMoveModifier.flags)
        case .excluded:
            return []
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $tab) {
                GeneralView(settings: settings)
                    .tabItem { Label("General", systemImage: "gearshape") }
                    .tag(Tab.general)

                ShortcutsView(store: bindings)
                    .tabItem { Label("Shortcuts", systemImage: "keyboard") }
                    .tag(Tab.shortcuts)

                WindowActionsView(settings: settings)
                    .tabItem { Label("Windows", systemImage: "macwindow.on.rectangle") }
                    .tag(Tab.windows)

                ExclusionsView(settings: settings)
                    .tabItem { Label("Excluded", systemImage: "eye.slash") }
                    .tag(Tab.excluded)
            }

            Divider()

            // Always on show: the symbols are unreadable until you can see
            // which key each one is.
            KeyboardMap(
                keys: litKeys,
                modifiers: litModifiers,
                order: $settings.settings.modifierRowOrder
            )
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
