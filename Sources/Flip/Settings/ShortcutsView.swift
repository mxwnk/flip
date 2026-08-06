import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ShortcutsView: View {
    @ObservedObject var store: BindingStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(store.bindings) { binding in
                        BindingRow(binding: binding, issue: store.issue(for: binding), store: store)
                        Divider().opacity(0.4)
                    }
                }
            }

            footer
        }
        .frame(minWidth: 460, minHeight: 320)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Hold Option and press a key to reach an application.")
                .font(.callout)
            Text("Pressing it again while that application is in front walks its windows.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var footer: some View {
        HStack {
            Button("Add Shortcut", systemImage: "plus") { store.add() }

            Spacer()

            // The file is the real configuration; the window is one way to edit it.
            Button("Reveal bindings.json") {
                NSWorkspace.shared.activateFileViewerSelecting([store.fileURL])
            }
            .buttonStyle(.link)
            .font(.caption)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

/// A field that holds exactly one key.
///
/// Clicking it empties it, and the first character typed is taken and hands focus
/// straight back. A plain text field would let you type a word into a slot that
/// can only ever hold one character, and leave you to notice.
///
/// Leaving without typing puts the old key back, so a stray click costs nothing.
private struct KeyField: View {
    let id: UUID
    @ObservedObject var store: BindingStore

    @FocusState private var isFocused: Bool
    @State private var text = ""

    var body: some View {
        TextField(isFocused ? "press" : "key", text: $text)
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.center)
            .frame(width: 54)
            .focused($isFocused)
            .onAppear { text = store.key(for: id) }
            .onChange(of: isFocused) { _, focused in
                text = focused ? "" : store.key(for: id)
            }
            .onChange(of: text) { _, typed in
                // Only the last character: typing fast, or pasting, should still
                // leave exactly one key behind rather than a rejected word.
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
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    /// A shadowed character is a warning — legal, occasionally deliberate. The
    /// others mean the binding does nothing at all.
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

    /// For everything not currently running, which the menu above cannot list.
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
