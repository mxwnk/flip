import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct LayoutsView: View {
    @ObservedObject var config: ConfigStore
    @State private var editingLayout: WindowLayout?
    @State private var isCreatingNew = false

    private var leader: ModifierChoice { config.settings.arrange.leader }

    var body: some View {
        Form {
            Section {
                LeaderPicker(choice: $config.settings.arrange.leader)
                    .padding(.vertical, 2)
            } header: {
                Text("Leader")
            } footer: {
                Caption("Held while you press the shortcut key of a layout preset. "
                    + "Shared with window arrangement shortcuts.")
            }

            Section {
                if config.settings.arrange.layouts.isEmpty {
                    Caption("No layout presets yet.")
                }

                ForEach(config.settings.arrange.layouts) { layout in
                    HStack(spacing: 8) {
                        Text(layout.name)
                            .font(.body.weight(.medium))

                        Spacer(minLength: 0)

                        if let key = layout.key, !key.isEmpty {
                            Keycap("\(leader.label) \(key.uppercased())")
                        }

                        Text("\(layout.rules.count) \(layout.rules.count == 1 ? "rule" : "rules")")
                            .foregroundStyle(.secondary)
                            .font(.callout)

                        Button("Edit") {
                            editingLayout = layout
                            isCreatingNew = false
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Button {
                            config.removeLayout(layout.id)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }

                Button("Add Layout", systemImage: "plus") {
                    editingLayout = WindowLayout(name: "New Layout", key: nil, rules: [])
                    isCreatingNew = true
                }
                .buttonStyle(.borderless)
            } header: {
                Text("Presets")
            } footer: {
                Caption("Hold \(leader.label) and press the shortcut key, or pick a layout from the menu bar to arrange and focus windows across your displays.")
            }
        }
        .formStyle(.grouped)
        .sheet(item: $editingLayout) { layout in
            LayoutEditorSheet(
                layout: layout,
                leader: leader.label,
                onSave: { updated in
                    if isCreatingNew {
                        config.addLayout(updated)
                    } else {
                        config.updateLayout(updated)
                    }
                    editingLayout = nil
                },
                onCancel: {
                    editingLayout = nil
                }
            )
        }
    }
}

private struct LayoutEditorSheet: View {
    @State var layout: WindowLayout
    let leader: String
    let onSave: (WindowLayout) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(layout.name.isEmpty ? "Layout Preset" : layout.name)
                    .font(.headline)

                Spacer()

                Button("Cancel", action: onCancel)

                Button("Done") {
                    onSave(layout)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(layout.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding()

            Divider()

            Form {
                Section {
                    TextField("Name", text: $layout.name)

                    HStack {
                        Text("Shortcut key")
                        Spacer()
                        Text(leader)
                            .foregroundStyle(.secondary)
                        TextField("key", text: Binding(
                            get: { layout.key ?? "" },
                            set: { newValue in
                                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                                layout.key = trimmed.isEmpty ? nil : String(trimmed.prefix(1)).lowercased()
                            }
                        ))
                        .frame(width: 50)
                        .multilineTextAlignment(.center)
                    }
                } header: {
                    Text("Preset details")
                } footer: {
                    Caption("The shortcut is triggered together with the arrange leader (\(leader)).")
                }

                Section {
                    if layout.rules.isEmpty {
                        Caption("No rules yet. Add rules to position specific applications.")
                    }

                    ForEach($layout.rules) { $rule in
                        LayoutRuleRow(rule: $rule) {
                            layout.rules.removeAll { $0.id == rule.id }
                        }
                    }

                    Button("Add Rule", systemImage: "plus") {
                        layout.rules.append(LayoutRule(bundleID: "", display: "primary", arrangement: .maximize))
                    }
                    .buttonStyle(.borderless)
                } header: {
                    Text("Window rules")
                } footer: {
                    Caption("When activated, Flip matches open windows to these rules and moves them to the chosen display and arrangement.")
                }
            }
            .formStyle(.grouped)
        }
        .frame(minWidth: 480, idealWidth: 520, minHeight: 380, idealHeight: 440)
    }
}

private struct LayoutRuleRow: View {
    @Binding var rule: LayoutRule
    let onDelete: () -> Void

    private let displays: [(id: String, label: String)] = [
        ("primary", "Primary display"),
        ("secondary", "Secondary display"),
        ("1", "Display 1"),
        ("2", "Display 2"),
        ("3", "Display 3"),
    ]

    private var arrangements: [WindowArrangement] {
        WindowArrangement.allCases.filter { !$0.movesToAnotherDisplay }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                applicationPicker

                Spacer(minLength: 0)

                Button(action: onDelete) {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                Picker("Display", selection: $rule.display) {
                    ForEach(displays, id: \.id) { d in
                        Text(d.label).tag(d.id)
                    }
                }
                .frame(width: 170)

                Picker("Arrangement", selection: $rule.arrangement) {
                    ForEach(arrangements, id: \.self) { arr in
                        Text(arr.title).tag(arr)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var applicationPicker: some View {
        Menu {
            ForEach(AppCatalog.running(), id: \.bundleID) { application in
                Button(application.name) {
                    rule.bundleID = application.bundleID
                }
            }

            Divider()
            Button("Choose Application…") { chooseApplication() }
        } label: {
            HStack(spacing: 6) {
                if let icon = AppCatalog.icon(for: rule.bundleID) {
                    Image(nsImage: icon).resizable().frame(width: 16, height: 16)
                }
                Text(rule.bundleID.isEmpty ? "Choose Application…" : AppCatalog.name(for: rule.bundleID))
                    .lineLimit(1)
            }
        }
        .menuStyle(.borderlessButton)
        .frame(maxWidth: .infinity, alignment: .leading)
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

        rule.bundleID = bundleID
    }
}
