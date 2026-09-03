import SwiftUI

/// Everything about the grid: what opens it, where it appears and what it shows.
/// General is left with the application itself.
struct SwitcherView: View {
    @ObservedObject var config: ConfigStore

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
                Picker("Show the grid on", selection: $config.settings.switcher.overlayPlacement) {
                    ForEach(OverlayPlacement.allCases) { choice in
                        Text(choice.label).tag(choice)
                    }
                }
            } footer: {
                Caption(config.settings.switcher.overlayPlacement == .everyDisplay
                    ? "The same grid on each one, so it is always where you are looking."
                    : "With two displays the grid can open on the one you are not looking at.")
            }

            Section {
                Picker("Show the overlay", selection: $config.settings.switcher.overlayDelay) {
                    ForEach(OverlayDelay.allCases) { choice in
                        Text(choice.label).tag(choice)
                    }
                }
            } footer: {
                Caption("A shorter tap switches windows without drawing anything.")
            }

            Section {
                Toggle("Show window thumbnails", isOn: $config.settings.switcher.showThumbnails)
            } footer: {
                Caption(config.settings.switcher.showThumbnails
                    ? "Captured through ScreenCaptureKit, which is why Flip asks for Screen Recording."
                    : "Application icons only. Flip no longer needs the Screen Recording grant.")
            }

            Section {
                Toggle(
                    "Show windows from every space",
                    isOn: $config.settings.switcher.showWindowsFromEverySpace
                )
            } footer: {
                Caption(config.settings.switcher.showWindowsFromEverySpace
                    ? "Choosing one switches to its space. A space's windows are learned the first time you visit it."
                    : "Only the space you are looking at. Minimised windows are listed either way.")
            }

            Section {
                Toggle(
                    "Group windows by application",
                    isOn: $config.settings.switcher.groupWindowsByApp
                )
            } footer: {
                Caption("Windows of the same application appear together in the switcher, "
                    + "ordered by most recently used application.")
            }
        }
        .formStyle(.grouped)
    }

    /// Written through so the two can never end up identical, which would leave
    /// one of them unmatchable: the router compares the modifier exactly, and
    /// the first of the two to be checked would answer for both.
    private var leader: Binding<ModifierChoice> {
        Binding(
            get: { config.settings.switcher.leader },
            set: { choice in
                if config.settings.switcher.applicationLeader == choice {
                    config.settings.switcher.applicationLeader = config.settings.switcher.leader
                }
                config.settings.switcher.leader = choice
            }
        )
    }

    private var appSwitcher: Binding<ModifierChoice> {
        Binding(
            get: { config.settings.switcher.applicationLeader },
            set: { choice in
                if config.settings.switcher.leader == choice {
                    config.settings.switcher.leader = config.settings.switcher.applicationLeader
                }
                config.settings.switcher.applicationLeader = choice
            }
        )
    }
}
