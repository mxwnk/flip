import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct InputSourcesView: View {
    @ObservedObject var config: ConfigStore

    /// Read once per visit: the list only changes in System Settings.
    @State private var available: [InputSource] = []

    var body: some View {
        Form {
            Section {
                if config.settings.inputSources.isEmpty {
                    Caption("No application has an input source of its own.")
                }

                ForEach(assignedBundleIDs, id: \.self, content: row)

                Menu {
                    ForEach(candidates, id: \.bundleID) { application in
                        Button(application.name) { assign(application.bundleID) }
                    }
                    Divider()
                    Button("Choose Application…") { chooseApplication() }
                } label: {
                    Label("Add Application", systemImage: "plus")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .disabled(available.isEmpty)
            } footer: {
                Caption("When one of these applications comes to the front, Flip switches to its "
                    + "input source. Every other application keeps whichever one is on.")
            }
        }
        .formStyle(.grouped)
        .onAppear { available = InputSources.enabled() }
    }

    private var assignedBundleIDs: [String] {
        config.settings.inputSources.keys.sorted {
            AppCatalog.name(for: $0).localizedStandardCompare(AppCatalog.name(for: $1)) == .orderedAscending
        }
    }

    private var candidates: [(bundleID: String, name: String)] {
        AppCatalog.running().filter { config.settings.inputSources[$0.bundleID] == nil }
    }

    /// Starts on the source that is on now, which is usually the one wanted.
    private func assign(_ bundleID: String) {
        guard let source = InputSources.currentID ?? available.first?.id else { return }

        config.setInputSource(source, for: bundleID)
    }

    private func row(for bundleID: String) -> some View {
        HStack(spacing: 10) {
            if let icon = AppCatalog.icon(for: bundleID) {
                Image(nsImage: icon).resizable().frame(width: 16, height: 16)
            }

            Text(AppCatalog.name(for: bundleID))
                .lineLimit(1)

            Spacer(minLength: 8)

            Picker("", selection: source(for: bundleID)) {
                ForEach(choices(for: bundleID)) { source in
                    Text(source.name).tag(source.id)
                }
            }
            .labelsHidden()
            .fixedSize()

            Button {
                config.removeInputSource(for: bundleID)
            } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
        }
    }

    private func source(for bundleID: String) -> Binding<String> {
        Binding(
            get: { config.settings.inputSources[bundleID] ?? "" },
            set: { config.setInputSource($0, for: bundleID) }
        )
    }

    /// A source disabled since it was chosen stays listed, or the menu would
    /// show nothing selected and hide what the file still says.
    private func choices(for bundleID: String) -> [InputSource] {
        guard let stored = config.settings.inputSources[bundleID],
              !available.contains(where: { $0.id == stored })
        else { return available }

        return available + [InputSource(id: stored, name: "\(stored) (not enabled)")]
    }

    private func chooseApplication() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Add"

        guard panel.runModal() == .OK, let url = panel.url,
              let bundleID = Bundle(url: url)?.bundleIdentifier
        else { return }

        assign(bundleID)
    }
}
