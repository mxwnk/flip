import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ExclusionsView: View {
    @ObservedObject var settings: SettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("These applications stay out of the window list. A key bound directly to one still reaches it.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

            if settings.settings.excludedBundleIDs.isEmpty {
                Spacer()
                Text("Nothing excluded")
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(settings.settings.excludedBundleIDs, id: \.self) { bundleID in
                            row(for: bundleID)
                            Divider().opacity(0.4)
                        }
                    }
                }
            }

            HStack {
                Menu {
                    ForEach(candidates, id: \.bundleID) { application in
                        Button(application.name) { settings.excluding(application.bundleID) }
                    }
                    Divider()
                    Button("Choose Application…") { chooseApplication() }
                } label: {
                    Label("Exclude Application", systemImage: "plus")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    /// Running applications that are not already excluded — offering one twice
    /// would just be a way to do nothing.
    private var candidates: [(bundleID: String, name: String)] {
        AppCatalog.running().filter { !settings.settings.excludedBundleIDs.contains($0.bundleID) }
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
                settings.stopExcluding(bundleID)
            } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
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

        settings.excluding(bundleID)
    }
}
