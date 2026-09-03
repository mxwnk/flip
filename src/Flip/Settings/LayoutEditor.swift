import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// One preset, edited whole: the sheet holds its own copy and hands it back on
/// Done, so cancelling out of a half-written rule leaves nothing behind.
struct LayoutEditor: View {
    @State var layout: WindowLayout
    let leader: ModifierChoice
    let isNew: Bool
    /// Raised while the key recorder is armed, or Flip's tap eats the keystroke.
    let onKeyCapture: ((Bool) -> Void)?
    let onSave: (WindowLayout) -> Void
    let onCancel: () -> Void

    @FocusState private var nameFocused: Bool

    private var trimmedName: String {
        layout.name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            Form {
                presetSection
                rulesSection
            }
            .formStyle(.grouped)

            Divider()

            footer
        }
        .frame(width: 680, height: 720)
        .onAppear { nameFocused = isNew }
    }

    private var header: some View {
        HStack(spacing: 12) {
            SettingsIcon(tab: .layouts, size: 30)

            VStack(alignment: .leading, spacing: 1) {
                Text(isNew ? "New Layout" : "Edit Layout")
                    .font(.system(size: 17, weight: .semibold))
                Caption(summary)
            }

            Spacer(minLength: 0)

            if let key = layout.key, !key.isEmpty {
                Keycap("\(leader.label) \(key.uppercased())")
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private var summary: String {
        let rules = layout.rules.count
        guard rules > 0 else { return "Name it, then add a rule for each application" }

        return "\(rules) \(rules == 1 ? "rule" : "rules") across your displays"
    }

    private var presetSection: some View {
        Section {
            LabeledContent("Name") {
                TextField("Layout name", text: $layout.name)
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.leading)
                    .focused($nameFocused)
                    .frame(maxWidth: 280)
            }

            LabeledContent("Shortcut") {
                HStack(spacing: 8) {
                    Text(leader.label)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)

                    KeyRecorder(
                        key: Binding(
                            get: { layout.key ?? "" },
                            set: { layout.key = $0.isEmpty ? nil : $0 }
                        ),
                        onCapture: onKeyCapture
                    )

                    Button("Clear") { layout.key = nil }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                        .disabled(layout.key?.isEmpty ?? true)
                }
            }
        } header: {
            Text("Preset")
        } footer: {
            Caption("Click the key and press the one you want. Holding \(leader.label) with it "
                + "applies the preset from anywhere; without a key it stays reachable from the "
                + "menu bar.")
        }
    }

    private var rulesSection: some View {
        Section {
            VStack(spacing: 10) {
                if layout.rules.isEmpty {
                    emptyRules
                }

                ForEach($layout.rules) { $rule in
                    LayoutRuleCard(rule: $rule) {
                        layout.rules.removeAll { $0.id == rule.id }
                    }
                }
            }
            .padding(.vertical, 2)
        } header: {
            HStack {
                Text("Window rules")

                Spacer()

                Button("Add Rule", systemImage: "plus", action: addRule)
                    .buttonStyle(.borderless)
                    .controlSize(.small)
            }
        } footer: {
            Caption("Each rule names one application and where its windows go. They are applied "
                + "in order, so the last rule ends up in front.")
        }
    }

    private var emptyRules: some View {
        VStack(spacing: 8) {
            Image(systemName: "rectangle.3.group")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(.tertiary)

            Caption("No rules yet. Add one for every application this layout should place.")
                .multilineTextAlignment(.center)

            Button("Add Rule", systemImage: "plus", action: addRule)
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(
                    Color.primary.opacity(0.14),
                    style: StrokeStyle(lineWidth: 1, dash: [4, 4])
                )
        )
    }

    private var footer: some View {
        HStack {
            Spacer()

            Button("Cancel", action: onCancel)
                .keyboardShortcut(.cancelAction)

            Button(isNew ? "Save" : "Done") { onSave(layout) }
                .keyboardShortcut(.defaultAction)
                .disabled(trimmedName.isEmpty)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private func addRule() {
        layout.rules.append(LayoutRule(bundleID: "", display: "primary", arrangement: .maximize))
    }
}

/// One rule as a card. Flat rows put the application, the display and the
/// arrangement on the same footing and read as three unrelated menus; the card
/// says which application the two menus underneath belong to.
private struct LayoutRuleCard: View {
    @Binding var rule: LayoutRule
    let onDelete: () -> Void

    private var arrangements: [WindowArrangement] {
        WindowArrangement.allCases.filter { !$0.movesToAnotherDisplay }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ArrangementPreview(arrangement: rule.arrangement, active: !rule.bundleID.isEmpty)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    applicationPicker

                    Spacer(minLength: 0)

                    Button(action: onDelete) {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .help("Remove this rule")
                }
                // Fixed, or the menu grows by the height of the icon it gains
                // and pushes the two below it down as you pick an application.
                .frame(height: 24)

                HStack(alignment: .top, spacing: 12) {
                    field("Display") {
                        Picker("", selection: $rule.display) {
                            ForEach(DisplayChoice.all(including: rule.display)) { choice in
                                Text(choice.label).tag(choice.id)
                            }
                        }
                        .labelsHidden()
                    }

                    field("Arrangement") {
                        Picker("", selection: $rule.arrangement) {
                            ForEach(arrangements, id: \.self) { arrangement in
                                Text(arrangement.title).tag(arrangement)
                            }
                        }
                        .labelsHidden()
                    }
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    /// The label above the control rather than beside it: two menus side by side
    /// with the words to their left is where it stops being clear which is which.
    private func field(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var applicationPicker: some View {
        Menu {
            ForEach(AppCatalog.running(), id: \.bundleID) { application in
                Button(application.name) { rule.bundleID = application.bundleID }
            }

            Divider()
            Button("Choose Application…") { chooseApplication() }
        } label: {
            HStack(spacing: 6) {
                // Both held open while there is no application yet. The icon is
                // taller than the text, so it appearing would otherwise push the
                // two menus underneath down the moment you pick one.
                Color.clear
                    .frame(width: 18, height: 18)
                    .overlay {
                        if let icon = AppCatalog.icon(for: rule.bundleID) {
                            Image(nsImage: icon).resizable()
                        }
                    }
                    .clipped()

                Text(rule.bundleID.isEmpty ? "Choose Application…" : AppCatalog.name(for: rule.bundleID))
                    .font(.body.weight(.medium))
                    .foregroundStyle(rule.bundleID.isEmpty ? .secondary : .primary)
                    .lineLimit(1)
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
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

/// The displays a rule can name. "Primary" and "secondary" follow the machine;
/// the numbered ones are the displays actually attached, named so the menu says
/// which screen it means rather than only which position.
struct DisplayChoice: Identifiable {
    let id: String
    let label: String

    static func all(including current: String) -> [DisplayChoice] {
        var choices = [
            DisplayChoice(id: "primary", label: "Primary display"),
            DisplayChoice(id: "secondary", label: "Secondary display"),
        ]

        for (index, screen) in ScreenGeometry.inArrangementOrder(NSScreen.screens, by: \.frame).enumerated() {
            choices.append(
                DisplayChoice(id: "\(index + 1)", label: "Display \(index + 1) — \(screen.localizedName)")
            )
        }

        // A preset written for a display that is unplugged right now still has to
        // show what it says, or the menu silently reads as the first entry.
        if !choices.contains(where: { $0.id == current }) {
            choices.append(DisplayChoice(id: current, label: "Display \(current) (not attached)"))
        }

        return choices
    }
}
