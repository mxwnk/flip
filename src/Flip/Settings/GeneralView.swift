import SwiftUI

struct GeneralView: View {
    @ObservedObject var settings: SettingsStore
    @State private var startsAtLogin = LoginItem.isEnabled

    var body: some View {
        Form {
            Section {
                Toggle("Start Flip at login", isOn: $startsAtLogin)
                    .onChange(of: startsAtLogin) { _, enabled in
                        LoginItem.setEnabled(enabled)
                        // The system has the last word, so the switch shows what
                        // actually happened rather than what was asked for.
                        startsAtLogin = LoginItem.isEnabled
                    }
            } footer: {
                if LoginItem.isBlockedBySystemSettings {
                    Caption(
                        "Turned off in System Settings › Login Items. Flip cannot override that from here.",
                        tone: .orange
                    )
                }
            }

            Section {
                Picker("Switch windows with", selection: leader) {
                    ForEach(ModifierChoice.allCases) { choice in
                        Text("\(choice.label) and Tab").tag(choice)
                    }
                }

                Picker("Switch within an application with", selection: appSwitcher) {
                    ForEach(ModifierChoice.allCases) { choice in
                        Text("\(choice.label) and Tab").tag(choice)
                    }
                }
            } footer: {
                Caption("The application keys use the first of these: hold it and press S for Spotify.")
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

            Section {
                Toggle("Check for updates", isOn: $settings.settings.checkForUpdates)
            } footer: {
                Caption("Asks GitHub once a day whether a newer release exists, and says so in the "
                    + "menu. Nothing is downloaded or installed.")
            }
        }
        .formStyle(.grouped)
    }

    /// Written through so the two hotkeys can never end up identical, which would
    /// make one of them unmatchable.
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
