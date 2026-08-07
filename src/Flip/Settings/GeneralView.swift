import SwiftUI

struct GeneralView: View {
    @ObservedObject var settings: SettingsStore
    @State private var startsAtLogin = LoginItem.isEnabled

    var body: some View {
        Form {
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
                Text("The application keys use the first of these: hold it and press S for Spotify.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("Show the overlay", selection: $settings.settings.overlayDelay) {
                    ForEach(OverlayDelay.allCases) { choice in
                        Text(choice.label).tag(choice)
                    }
                }
            } footer: {
                Text("A shorter tap switches windows without drawing anything.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Show window thumbnails", isOn: $settings.settings.showThumbnails)
            } footer: {
                Text(settings.settings.showThumbnails
                    ? "Captured through ScreenCaptureKit, which is why Flip asks for Screen Recording."
                    : "Application icons only. Flip no longer needs the Screen Recording grant.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle(
                    "Show windows from every space",
                    isOn: $settings.settings.showWindowsFromEverySpace
                )
            } footer: {
                Text(settings.settings.showWindowsFromEverySpace
                    ? "Choosing one switches to its space. A space's windows are learned the first time you visit it."
                    : "Only the space you are looking at. Minimised windows are listed either way.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

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
                    Text("Turned off in System Settings › Login Items. Flip cannot override that from here.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
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
