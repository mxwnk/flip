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
        // The sidebar runs all the way up behind the traffic lights, which is
        // the whole look. A title bar drawn over it would cut it in two, and the
        // window's name is already the first thing in the sidebar.
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden

        let host = NSHostingView(rootView: SettingsView(settings: settings, bindings: bindings))
        // Otherwise the hosting view sizes to the content's ideal size, which
        // for a list is every row at once.
        host.sizingOptions = []
        window.contentView = host

        // A comfortable floor, not a required one: every page scrolls. Wider
        // than it was, because the sidebar now takes a column of its own.
        window.contentMinSize = NSSize(width: 700, height: 620)
        window.setContentSize(NSSize(width: 780, height: 760))
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

    @State private var tab: SettingsTab = .general

    /// What the keyboard lights up, per tab. All bindings at once would be half
    /// the keys lit and no meaning.
    private var litKeys: Set<CGKeyCode> {
        switch tab {
        case .general:
            // Nothing on that page is a key, and a keyboard lit for a page it
            // has nothing to do with is worse than one left dark.
            return []
        case .switcher:
            return [CGKeyCode(kVK_Tab)]
        case .shortcuts:
            return Set(bindings.bindings.compactMap { KeyboardLayout.keyCode(forBinding: $0.key) })
        case .windows:
            return Set(
                WindowArrangement.shortcuts(
                    navigation: settings.settings.windowLeader,
                    displayMove: settings.settings.displayMoveModifier
                )
                    .map(\.keyCode)
            )
        case .excluded:
            return []
        }
    }

    private var litModifiers: CGEventFlags {
        switch tab {
        case .general:
            return []
        case .switcher:
            return settings.settings.leader.flags.union(settings.settings.appSwitcher.flags)
        case .shortcuts:
            return settings.settings.shortcutLeader.flags
        case .windows:
            return settings.settings.windowLeader.flags
                .union(settings.settings.displayMoveModifier.flags)
        case .excluded:
            return []
        }
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .navigationSplitViewStyle(.balanced)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// General on its own above the group: it is the page about Flip as a
    /// whole, where the other three are each about one part of it.
    private var sidebar: some View {
        List(selection: $tab) {
            row(.general)

            Section("Settings") {
                row(.switcher)
                row(.shortcuts)
                row(.windows)
                row(.excluded)
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 190, ideal: 205, max: 240)
        // A split view fits itself a collapse button. Four pages that are the
        // only way to reach any of this is not something to be able to fold
        // away, and the title bar is otherwise empty on purpose.
        .toolbar(removing: .sidebarToggle)
    }

    private func row(_ tab: SettingsTab) -> some View {
        Label {
            Text(tab.title)
        } icon: {
            SettingsIcon(tab: tab)
        }
        .padding(.vertical, 3)
        .tag(tab)
    }

    private var detail: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                SettingsIcon(tab: tab, size: 26)
                Text(tab.title).font(.system(size: 19, weight: .semibold))

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)

            page

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
    }

    @ViewBuilder
    private var page: some View {
        switch tab {
        case .general: GeneralView(settings: settings)
        case .switcher: SwitcherView(settings: settings)
        case .shortcuts: ShortcutsView(store: bindings, settings: settings)
        case .windows: WindowActionsView(settings: settings)
        case .excluded: ExclusionsView(settings: settings)
        }
    }
}
