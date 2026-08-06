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

    private static let file = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Flip", isDirectory: true)
        .appendingPathComponent("settings.json")

    var fileURL: URL { Self.file }

    func load() {
        guard let data = try? Data(contentsOf: Self.file) else {
            log.notice("no settings file yet, writing the defaults")
            save()
            return
        }

        do {
            // Through the property, so an older file missing keys is written back
            // complete.
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
                at: Self.file.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try encoder.encode(settings).write(to: Self.file, options: .atomic)
        } catch {
            log.error("could not save settings: \(error.localizedDescription, privacy: .public)")
        }
    }
}
