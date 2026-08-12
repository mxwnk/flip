import SwiftUI

/// The two modifiers, then the keys they carry. The keys themselves stay put:
/// four corners need four keys that form a square, and moving those around is a
/// different question from which modifier you hold.
struct WindowActionsView: View {
    @ObservedObject var settings: SettingsStore

    private var navigation: ModifierChoice { settings.settings.windowLeader }

    /// Split so each modifier is listed with the keys it actually carries, which
    /// is the only way to see that the two do not tread on each other.
    private var shortcuts: [WindowShortcut] {
        WindowArrangement.shortcuts(
            navigation: navigation, displayMove: settings.settings.displayMoveModifier
        )
    }

    var body: some View {
        Form {
            Section {
                LeaderPicker(choice: $settings.settings.displayMoveModifier)
                    .padding(.vertical, 2)

                ForEach(shortcuts.filter(\.arrangement.movesToAnotherDisplay)) { shortcut in
                    LabeledContent(shortcut.name) { Keycap(shortcut.keys) }
                }
            } header: {
                Text("Move to another display")
            } footer: {
                Caption("The window keeps its place on the display it lands on, proportionally, "
                    + "so a left half stays a left half. These share the arrows with the halves "
                    + "below, which is why they carry a modifier of their own — and neither "
                    + "choice here can ever be one of theirs.")
            }

            Section {
                LeaderPicker(choice: $settings.settings.windowLeader)
                    .padding(.vertical, 2)

                ForEach(shortcuts.filter { !$0.arrangement.movesToAnotherDisplay }) { shortcut in
                    LabeledContent(shortcut.name) { Keycap(shortcut.keys) }
                }
            } header: {
                Text("Move and resize")
            } footer: {
                VStack(alignment: .leading, spacing: 8) {
                    if navigation.takesArrowKeys {
                        Caption("\(navigation.label) and an arrow already means something on "
                            + "macOS: option moves by word, control switches spaces, command "
                            + "goes to the end of the line. Bound here, that is taken away "
                            + "everywhere.", tone: .orange)
                    }

                    Caption("Everything stops at the menu bar and the Dock. Filling is a toggle: "
                        + "press it on a window that already fills and it goes back where it "
                        + "was. The corners take u i j k because those four sit as a square on "
                        + "the keyboard.")
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
