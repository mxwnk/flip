import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ShortcutsView: View {
    @ObservedObject var config: ConfigStore

    private var leader: ModifierChoice { config.settings.shortcuts.leader }

    var body: some View {
        Form {
            Section {
                LeaderPicker(choice: $config.settings.shortcuts.leader)
                    .padding(.vertical, 2)
            } header: {
                Text("Leader")
            } footer: {
                if leader.takesMenuShortcuts {
                    Caption("\(leader.label) and a letter is a menu shortcut in every "
                        + "application. A key bound here takes that one away everywhere — "
                        + "\(leader.label)S no longer saves.", tone: .orange)
                } else {
                    Caption("Held while you press one of the keys below. The switcher's own "
                        + "leader is set on the Switcher page and can be a different key.")
                }
            }

            Section {
                if config.bindings.isEmpty {
                    // Every other page says when it is empty.
                    Caption("No shortcuts yet.")
                }

                ForEach(config.bindings) { binding in
                    BindingRow(
                        binding: binding,
                        issue: config.issue(
                            for: binding,
                            leader: leader.flags,
                            arrangeLeader: config.settings.arrange.leader,
                            displayMove: config.settings.arrange.displayMove,
                            arrangeKeys: config.settings.arrange.keys
                        ),
                        leader: leader.label,
                        config: config
                    )
                }

                Button("Add Shortcut", systemImage: "plus") { config.add() }
                    .buttonStyle(.borderless)
            } footer: {
                Caption("Hold \(leader.label) and press a key to reach an application. "
                    + "Pressing it again while that application is in front walks its "
                    + "windows. Click a key to record another one; F1 to F12 count.")
            }
        }
        .formStyle(.grouped)
    }
}

private struct BindingRow: View {
    let binding: AppBinding
    let issue: ConfigStore.Issue?
    /// Passed in, or the row claims ⌥ whatever the leader actually is.
    let leader: String
    @ObservedObject var config: ConfigStore

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Text(binding.usesLeader ? leader : "")
                    .foregroundStyle(.secondary)
                    .frame(width: 26)

                KeyRecorder(
                    key: Binding(
                        get: { config.key(for: binding.id) },
                        set: { config.setKey($0, for: binding.id) }
                    ),
                    onCapture: config.onKeyCapture
                )

                applicationPicker

                Spacer(minLength: 0)

                Button {
                    config.remove(binding.id)
                } label: {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
            }

            if let issue {
                Label(issue.message, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(severity)
                    .padding(.leading, 24)
            }
        }
    }

    /// Shadowing is legal and sometimes deliberate; the others mean the binding
    /// does nothing.
    private var severity: Color {
        if case .shadowsCharacter = issue { return .orange }

        return .red
    }

    private var applicationPicker: some View {
        Menu {
            ForEach(AppCatalog.running(), id: \.bundleID) { application in
                Button(application.name) {
                    config.setBundleID(application.bundleID, for: binding.id)
                }
            }

            Divider()
            Button("Choose Application…") { chooseApplication() }
        } label: {
            HStack(spacing: 6) {
                if let icon = AppCatalog.icon(for: binding.bundleID) {
                    Image(nsImage: icon).resizable().frame(width: 16, height: 16)
                }
                Text(binding.bundleID.isEmpty ? "Choose…" : AppCatalog.name(for: binding.bundleID))
                    .lineLimit(1)
            }
        }
        .menuStyle(.borderlessButton)
        .frame(width: 240, alignment: .leading)
    }

    private func chooseApplication() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"

        guard panel.runModal() == .OK, let url = panel.url,
              let bundle = Bundle(url: url), let bundleID = bundle.bundleIdentifier
        else { return }

        config.setBundleID(bundleID, for: binding.id)
    }
}
