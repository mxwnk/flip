import SwiftUI

/// The two modifiers, then the keys they carry. The keys themselves stay put:
/// four corners need four keys that form a square, and moving those around is a
/// different question from which modifier you hold.
struct WindowActionsView: View {
    @ObservedObject var settings: SettingsStore

    private var navigation: ModifierChoice { settings.settings.windowLeader }

    var body: some View {
        Form {
            Section {
                LeaderPicker(choice: $settings.settings.displayMoveModifier)
                    .padding(.vertical, 2)
            } header: {
                Text("Move to another display")
            } footer: {
                Caption("Held with ← and →. It shares those arrows with the halves below, so "
                    + "it carries a modifier of its own — and neither choice here can be one "
                    + "of theirs.")
            }

            Section {
                LeaderPicker(choice: $settings.settings.windowLeader)
                    .padding(.vertical, 2)
            } header: {
                Text("Move and resize")
            } footer: {
                if navigation.takesArrowKeys {
                    Caption("\(navigation.label) and an arrow already means something on macOS: "
                        + "option moves by word, control switches spaces, command goes to the "
                        + "end of the line. Bound here, that is taken away everywhere.",
                        tone: .orange)
                } else {
                    Caption("Held with the arrows, the four corner keys and return.")
                }
            }

            Section {
                ForEach(WindowArrangement.shortcuts(
                    navigation: navigation, displayMove: settings.settings.displayMoveModifier
                )) { shortcut in
                    LabeledContent(shortcut.name) { Keycap(shortcut.keys) }
                }
            } footer: {
                Caption("Halves and filling stop at the menu bar and the Dock. Filling a "
                    + "window that already fills puts it back where it was. The corners take "
                    + "u i j k because those four sit as a square on the keyboard.")
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
            .foregroundStyle(.primary)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            // Raised rather than recessed: a key you are being told to press
            // reads better as one standing up than as a hole in the row.
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .shadow(color: .black.opacity(0.12), radius: 1, y: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
            )
    }
}
