import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ShortcutsView: View {
    @ObservedObject var store: BindingStore

    var body: some View {
        Form {
            Section {
                if store.bindings.isEmpty {
                    // The other tabs say when they are empty; this one used to show
                    // a blank space and leave you guessing.
                    Caption("No shortcuts yet.")
                }

                ForEach(store.bindings) { binding in
                    BindingRow(binding: binding, issue: store.issue(for: binding), store: store)
                }

                Button("Add Shortcut", systemImage: "plus") { store.add() }
                    .buttonStyle(.borderless)
            } footer: {
                HStack(alignment: .firstTextBaseline) {
                    Caption("Hold Option and press a key to reach an application. Pressing it "
                        + "again while that application is in front walks its windows.")

                    Spacer(minLength: 16)

                    Button("Reveal bindings.json") {
                        NSWorkspace.shared.activateFileViewerSelecting([store.fileURL])
                    }
                    .buttonStyle(.link)
                    .font(.caption)
                    .fixedSize()
                }
            }
        }
        .formStyle(.grouped)
    }
}

/// Clicking empties it, the first character typed commits and hands focus back.
/// Leaving without typing restores the old key, so a stray click costs nothing.
private struct KeyField: View {
    let id: UUID
    @ObservedObject var store: BindingStore

    @FocusState private var isFocused: Bool
    @State private var text = ""

    var body: some View {
        TextField(isFocused ? "press" : "key", text: $text)
            // Without this the form lifts the placeholder into its label column
            // and every row lines up differently.
            .labelsHidden()
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.center)
            .frame(width: 54)
            .focused($isFocused)
            .onAppear { text = store.key(for: id) }
            .onChange(of: isFocused) { _, focused in
                text = focused ? "" : store.key(for: id)
            }
            .onChange(of: text) { _, typed in
                // Last character only, so pasting leaves one key rather than a
                // rejected word.
                guard isFocused, let character = typed.last else { return }

                store.setKey(String(character), for: id)
                isFocused = false
            }
    }
}

private struct BindingRow: View {
    let binding: AppBinding
    let issue: BindingStore.Issue?
    @ObservedObject var store: BindingStore

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Text(binding.usesLeader ? "⌥" : "")
                    .foregroundStyle(.secondary)
                    .frame(width: 14)

                KeyField(id: binding.id, store: store)

                applicationPicker

                Spacer(minLength: 0)

                Button {
                    store.remove(binding.id)
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
                    store.setBundleID(application.bundleID, for: binding.id)
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

        store.setBundleID(bundleID, for: binding.id)
    }
}
