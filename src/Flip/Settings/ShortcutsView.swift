import AppKit
import Carbon.HIToolbox
import SwiftUI
import UniformTypeIdentifiers

struct ShortcutsView: View {
    @ObservedObject var store: BindingStore
    @ObservedObject var settings: SettingsStore

    var body: some View {
        Form {
            Section {
                if store.bindings.isEmpty {
                    // The other tabs say when they are empty; this one used to show
                    // a blank space and leave you guessing.
                    Caption("No shortcuts yet.")
                }

                ForEach(store.bindings) { binding in
                    BindingRow(
                        binding: binding,
                        issue: store.issue(
                            for: binding,
                            leader: settings.settings.leader.flags,
                            displayMove: settings.settings.displayMoveModifier
                        ),
                        store: store
                    )
                }

                Button("Add Shortcut", systemImage: "plus") { store.add() }
                    .buttonStyle(.borderless)
            } footer: {
                HStack(alignment: .firstTextBaseline) {
                    Caption("Hold Option and press a key to reach an application. Pressing it "
                        + "again while that application is in front walks its windows. Click a "
                        + "key to record another one; F1 to F12 count.")

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

/// Click, then press the key. A text field could only ever be given characters,
/// and F1 to F12 are perfectly good bindings — `bindings.json` could name them
/// but this editor could not.
///
/// Escape gives up, and so does clicking it a second time. Recording swallows
/// the keystroke, so nothing is typed into the settings window on the way past.
private struct KeyRecorder: View {
    let id: UUID
    @ObservedObject var store: BindingStore

    @State private var isRecording = false
    @State private var monitor: Any?
    /// Which recording a pending timeout belongs to, so the one it was armed for
    /// is the only one it can end.
    @State private var session = 0

    var body: some View {
        Button { isRecording ? stop() : start() } label: {
            Text(isRecording ? "press" : label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(ink)
                .lineLimit(1)
                .frame(width: 54, height: 22)
                .background(RoundedRectangle(cornerRadius: 5).fill(fill))
        }
        .buttonStyle(.plain)
        .onDisappear(perform: stop)
    }

    private var label: String {
        let key = store.key(for: id)

        return key.isEmpty ? "key" : key.uppercased()
    }

    /// Lit the same way as the keyboard below, where this key is about to light
    /// up too.
    private var fill: Color {
        isRecording ? Theme.selectedStroke : Color.primary.opacity(0.07)
    }

    private var ink: Color {
        if isRecording { return .white }

        return store.key(for: id).isEmpty ? .secondary : .primary
    }

    private func start() {
        guard monitor == nil else { return }

        session += 1
        let armed = session
        isRecording = true
        store.onKeyCapture?(true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            record(event)

            return nil
        }

        // Left armed it would keep Flip's own keys switched off, and nothing
        // about the settings window would say why.
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            guard session == armed else { return }

            stop()
        }
    }

    private func record(_ event: NSEvent) {
        defer { stop() }

        guard Int(event.keyCode) != kVK_Escape,
              let key = KeyboardLayout.bindingKey(for: CGKeyCode(event.keyCode))
        else { return }

        store.setKey(key, for: id)
    }

    private func stop() {
        guard let monitor else { return }

        NSEvent.removeMonitor(monitor)
        self.monitor = nil
        isRecording = false
        session += 1
        store.onKeyCapture?(false)
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

                KeyRecorder(id: binding.id, store: store)

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
