import SwiftUI

/// Read-only for now: these keys are fixed, and a list that looked editable but
/// was not would be worse than one that says so.
struct WindowActionsView: View {
    @ObservedObject var settings: SettingsStore

    var body: some View {
        Form {
            Section {
                Picker("Move to another display with", selection: $settings.settings.displayMoveModifier) {
                    ForEach(DisplayMoveModifier.allCases) { choice in
                        Text(choice.label).tag(choice)
                    }
                }
            } footer: {
                Caption("The only one of these that is settable. The halves and "
                    + "quarters share the arrow keys with it, so it needs a modifier "
                    + "of its own.")
            }

            Section {
                ForEach(WindowArrangement.shortcuts(displayMove: settings.settings.displayMoveModifier)) { shortcut in
                    LabeledContent(shortcut.name) { Keycap(shortcut.keys) }
                }
            } footer: {
                // Both in the footer rather than a second section: a note in a card
                // of its own reads as a group of settings that forgot its controls.
                VStack(alignment: .leading, spacing: 8) {
                    Caption("Halves and filling stop at the menu bar and the Dock. Filling a "
                        + "window that already fills puts it back where it was.")
                    Caption("The halves and quarters cannot be changed. Every single modifier "
                        + "is already taken with the arrows: Option moves by word, Control "
                        + "switches spaces, fn is Home and End, and Command is the start and "
                        + "end of a line — so two of them is what is left, and there is no "
                        + "second pair to offer.")
                }
            }
        }
        .formStyle(.grouped)
    }
}

/// The key combination as something that reads like a key, not like a label.
struct Keycap: View {
    private let keys: String

    init(_ keys: String) {
        self.keys = keys
    }

    var body: some View {
        Text(keys)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.primary.opacity(0.07))
            )
    }
}
