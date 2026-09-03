import AppKit
import SwiftUI

struct LayoutsView: View {
    @ObservedObject var config: ConfigStore
    @State private var editing: WindowLayout?

    private var leader: ModifierChoice { config.settings.arrange.leader }

    var body: some View {
        Form {
            Section {
                LeaderPicker(choice: $config.settings.arrange.leader)
                    .padding(.vertical, 2)
            } header: {
                Text("Leader")
            } footer: {
                Caption("Held while you press the key of a layout preset. The same leader as the "
                    + "one on the Arrange page, which is why a key already taken there can never "
                    + "reach a preset.")
            }

            Section {
                if config.settings.arrange.layouts.isEmpty {
                    Caption("No layout presets yet.")
                }

                ForEach(config.settings.arrange.layouts) { layout in
                    LayoutRow(layout: layout, leader: leader, issue: issue(for: layout)) {
                        editing = layout
                    } onDelete: {
                        config.removeLayout(layout.id)
                    }
                }

                Button("Add Layout", systemImage: "plus") {
                    editing = WindowLayout(name: "", key: nil, rules: [])
                }
                .buttonStyle(.borderless)
            } header: {
                Text("Presets")
            } footer: {
                Caption("Hold \(leader.label) and press a preset's key, or pick one from the menu "
                    + "bar, to move every application it names onto its display and bring the "
                    + "whole set forward.")
            }
        }
        .formStyle(.grouped)
        .sheet(item: $editing) { layout in
            LayoutEditor(
                layout: layout,
                leader: leader,
                isNew: !config.hasLayout(layout.id),
                onKeyCapture: config.onKeyCapture,
                onSave: { updated in
                    config.saveLayout(updated)
                    editing = nil
                },
                onCancel: { editing = nil }
            )
        }
    }

    /// A preset that cannot fire looks exactly like one that can, so the reasons
    /// it will not are said here rather than found by pressing the key.
    private func issue(for layout: WindowLayout) -> String? {
        let layouts = config.settings.arrange.layouts

        if let key = layout.key, !key.isEmpty {
            // Arrangements are matched first, so this key never reaches here.
            if let taken = config.settings.arrange.keys.first(where: { $0.value == key })?.key,
               !taken.movesToAnotherDisplay {
                return "\(leader.label)\(key.uppercased()) already means \(taken.title.lowercased())."
            }

            if layouts.contains(where: { $0.id != layout.id && $0.key == key }) {
                return "Another preset uses the same key."
            }
        }

        if layouts.contains(where: { $0.id != layout.id && $0.name == layout.name }) {
            return "Another preset has the same name; the menu bar cannot tell them apart."
        }

        return layout.rules.isEmpty ? "No rules yet, so this preset does nothing." : nil
    }
}

private struct LayoutRow: View {
    let layout: WindowLayout
    let leader: ModifierChoice
    let issue: String?
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                icons

                Text(layout.name)
                    .font(.body.weight(.medium))

                Spacer(minLength: 8)

                if let key = layout.key, !key.isEmpty {
                    Keycap("\(leader.label) \(key.uppercased())")
                }

                Text("\(layout.rules.count) \(layout.rules.count == 1 ? "rule" : "rules")")
                    .foregroundStyle(.secondary)
                    .font(.callout)
                    .frame(width: 52, alignment: .trailing)

                Button("Edit", action: onEdit)
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                Button(action: onDelete) {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Remove this preset")
            }

            if let issue {
                Label(issue, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(.leading, 2)
            }
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: onEdit)
    }

    /// What the preset holds, without opening it. Overlapped rather than spaced:
    /// four icons in a row read as four separate rules of their own.
    private var icons: some View {
        let bundleIDs = layout.rules.map(\.bundleID).filter { !$0.isEmpty }.prefix(4)

        return HStack(spacing: -6) {
            ForEach(Array(bundleIDs.enumerated()), id: \.offset) { _, bundleID in
                if let icon = AppCatalog.icon(for: bundleID) {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 18, height: 18)
                }
            }
        }
        .frame(width: 48, alignment: .leading)
    }
}
