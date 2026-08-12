import SwiftUI

/// Everything about the grid: what opens it, where it appears and what it shows.
/// General is left with the application itself.
struct SwitcherView: View {
    @ObservedObject var settings: SettingsStore

    var body: some View {
        Form {
            Section {
                LeaderPicker(choice: leader)
                    .padding(.vertical, 2)
            } header: {
                Text("Switch windows")
            } footer: {
                Caption("Held with Tab. Every window on the space, most recently used first — "
                    + "add ⇧ to walk it backwards.")
            }

            Section {
                LeaderPicker(choice: appSwitcher)
                    .padding(.vertical, 2)
            } header: {
                Text("Switch within an application")
            } footer: {
                Caption("Also held with Tab, but only the windows of whichever application is "
                    + "in front. Picking the one above swaps them, since the two cannot be the "
                    + "same key.")
            }

            Section {
                Picker("Show the grid on", selection: $settings.settings.overlayPlacement) {
                    ForEach(OverlayPlacement.allCases) { choice in
                        Text(choice.label).tag(choice)
                    }
                }
            } footer: {
                Caption(settings.settings.overlayPlacement == .everyDisplay
                    ? "The same grid on each one, so it is always where you are looking."
                    : "With two displays the grid can open on the one you are not looking at.")
            }

            Section {
                Picker("Show the overlay", selection: $settings.settings.overlayDelay) {
                    ForEach(OverlayDelay.allCases) { choice in
                        Text(choice.label).tag(choice)
                    }
                }
            } footer: {
                Caption("A shorter tap switches windows without drawing anything.")
            }

            Section {
                Toggle("Show window thumbnails", isOn: $settings.settings.showThumbnails)
            } footer: {
                Caption(settings.settings.showThumbnails
                    ? "Captured through ScreenCaptureKit, which is why Flip asks for Screen Recording."
                    : "Application icons only. Flip no longer needs the Screen Recording grant.")
            }

            Section {
                Toggle(
                    "Show windows from every space",
                    isOn: $settings.settings.showWindowsFromEverySpace
                )
            } footer: {
                Caption(settings.settings.showWindowsFromEverySpace
                    ? "Choosing one switches to its space. A space's windows are learned the first time you visit it."
                    : "Only the space you are looking at. Minimised windows are listed either way.")
            }
        }
        .formStyle(.grouped)
    }

    /// Written through so the two can never end up identical, which would leave
    /// one of them unmatchable: the router compares the modifier exactly, and
    /// the first of the two to be checked would answer for both.
    private var leader: Binding<ModifierChoice> {
        Binding(
            get: { settings.settings.leader },
            set: { choice in
                if settings.settings.appSwitcher == choice {
                    settings.settings.appSwitcher = settings.settings.leader
                }
                settings.settings.leader = choice
            }
        )
    }

    private var appSwitcher: Binding<ModifierChoice> {
        Binding(
            get: { settings.settings.appSwitcher },
            set: { choice in
                if settings.settings.leader == choice {
                    settings.settings.leader = settings.settings.appSwitcher
                }
                settings.settings.appSwitcher = choice
            }
        )
    }
}
