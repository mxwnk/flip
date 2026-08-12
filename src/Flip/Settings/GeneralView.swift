import SwiftUI

/// The application itself. Everything about the grid it draws is on the
/// Switcher page.
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
                } else {
                    Caption("Flip has no Dock icon and never takes focus, so the menu bar is "
                        + "where it lives.")
                }
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
}
