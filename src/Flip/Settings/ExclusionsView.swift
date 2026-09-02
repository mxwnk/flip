import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ExclusionsView: View {
    @ObservedObject var config: ConfigStore

    var body: some View {
        Form {
            Section {
                if config.settings.excluded.isEmpty {
                    Caption("Nothing excluded.")
                }

                ForEach(config.settings.excluded, id: \.self, content: row)

                Menu {
                    ForEach(candidates, id: \.bundleID) { application in
                        Button(application.name) { config.excluding(application.bundleID) }
                    }
                    Divider()
                    Button("Choose Application…") { chooseApplication() }
                } label: {
                    Label("Exclude Application", systemImage: "plus")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            } footer: {
                Caption("These applications stay out of the window list. A key bound directly to "
                    + "one still reaches it.")
            }
        }
        .formStyle(.grouped)
    }

    private var candidates: [(bundleID: String, name: String)] {
        AppCatalog.running().filter { !config.settings.excluded.contains($0.bundleID) }
    }

    private func row(for bundleID: String) -> some View {
        HStack(spacing: 10) {
            if let icon = AppCatalog.icon(for: bundleID) {
                Image(nsImage: icon).resizable().frame(width: 16, height: 16)
            }

            Text(AppCatalog.name(for: bundleID))
                .lineLimit(1)

            Spacer(minLength: 0)

            Button {
                config.stopExcluding(bundleID)
            } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
        }
    }

    private func chooseApplication() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Exclude"

        guard panel.runModal() == .OK, let url = panel.url,
              let bundleID = Bundle(url: url)?.bundleIdentifier
        else { return }

        config.excluding(bundleID)
    }
}
