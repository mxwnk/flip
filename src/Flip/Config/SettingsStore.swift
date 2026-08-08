import Foundation
import OSLog

/// Next to BindingStore on disk, so the configuration is two readable files.
@MainActor
final class SettingsStore: ObservableObject {
    @Published var settings = Settings() {
        didSet {
            guard settings != oldValue else { return }

            save()
            onChange?()
        }
    }

    var onChange: (() -> Void)?

    private let log = Logger(subsystem: Bundle.identifier, category: "settings")

    /// Injectable so tests cannot write over the real configuration.
    let fileURL: URL

    init(file: URL = ApplicationSupport.file("settings.json")) {
        self.fileURL = file
    }

    func load() {
        guard let data = try? Data(contentsOf: fileURL) else {
            log.notice("no settings file yet, writing the defaults")
            save()
            return
        }

        do {
            // Through the property, so an older file is written back complete.
            settings = try JSONDecoder().decode(Settings.self, from: data)
        } catch {
            log.error("settings unreadable (\(error.localizedDescription, privacy: .public)), using defaults")
        }
    }

    func excluding(_ bundleID: String) {
        guard !settings.excludedBundleIDs.contains(bundleID) else { return }

        settings.excludedBundleIDs.append(bundleID)
    }

    func stopExcluding(_ bundleID: String) {
        settings.excludedBundleIDs.removeAll { $0 == bundleID }
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]

        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try encoder.encode(settings).write(to: fileURL, options: .atomic)
        } catch {
            log.error("could not save settings: \(error.localizedDescription, privacy: .public)")
        }
    }
}
