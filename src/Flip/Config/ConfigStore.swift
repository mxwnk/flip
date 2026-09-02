import CoreGraphics
import Foundation
import OSLog

/// The configuration, as readable JSON in Application Support: inspectable,
/// diffable, portable between machines. One file and one writer, so every save
/// is the whole document.
@MainActor
final class ConfigStore: ObservableObject {
    @Published var settings = Settings() {
        didSet {
            guard !isApplying, settings != oldValue else { return }

            commit()
        }
    }

    @Published private(set) var bindings: [AppBinding] = []

    var onChange: (() -> Void)?

    /// Raised while the settings window waits for a key. Flip's own tap would
    /// otherwise swallow one already bound bare, F1 above all.
    var onKeyCapture: ((Bool) -> Void)?

    private let log = Logger(subsystem: Bundle.identifier, category: "config")

    /// Injectable so tests cannot write over the real configuration.
    let fileURL: URL

    init(file: URL = ApplicationSupport.file("config.json")) {
        self.fileURL = file
    }

    // MARK: - Loading and saving

    func load() {
        guard let data = try? Data(contentsOf: fileURL) else {
            seed()
            return
        }

        do {
            apply(try JSONDecoder().decode(Config.self, from: data))
            log.notice("loaded \(self.bindings.count, privacy: .public) bindings")
            // A file written by an older version is written back complete.
            save()
        } catch {
            // Defaults beat no hotkeys; the broken file is left for inspection.
            log.error("config unreadable (\(error.localizedDescription, privacy: .public)), using defaults")
            apply(Config())
        }
    }

    /// A fresh install, or the two files Flip kept before this one. Those are
    /// removed only once the merged file is on disk.
    private func seed() {
        let settings = decode(Settings.self, from: legacySettingsFile)
        let bindings = decode([AppBinding].self, from: legacyBindingsFile)

        guard settings != nil || bindings != nil else {
            log.notice("no config file yet, writing the defaults")
            apply(Config())
            save()
            return
        }

        log.notice("merging settings.json and bindings.json into config.json")
        apply(Config(settings: settings ?? Settings(), bindings: bindings ?? DefaultBindings.all))
        guard save() else { return }

        try? FileManager.default.removeItem(at: legacySettingsFile)
        try? FileManager.default.removeItem(at: legacyBindingsFile)
    }

    private var legacySettingsFile: URL {
        fileURL.deletingLastPathComponent().appendingPathComponent("settings.json")
    }

    private var legacyBindingsFile: URL {
        fileURL.deletingLastPathComponent().appendingPathComponent("bindings.json")
    }

    private func decode<T: Decodable>(_ type: T.Type, from file: URL) -> T? {
        guard let data = try? Data(contentsOf: file) else { return nil }

        return try? JSONDecoder().decode(type, from: data)
    }

    private var isApplying = false

    /// Both halves at once, without the save the settings would otherwise
    /// trigger halfway through.
    private func apply(_ config: Config) {
        isApplying = true
        bindings = config.bindings
        settings = config.settings
        isApplying = false
    }

    @discardableResult
    private func save() -> Bool {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]

        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try encoder.encode(Config(settings: settings, bindings: bindings))
            try data.write(to: fileURL, options: .atomic)
            lastWritten = data

            return true
        } catch {
            log.error("could not save the configuration: \(error.localizedDescription, privacy: .public)")

            return false
        }
    }

    // MARK: - Noticing edits made by hand

    private var watcher: DispatchSourceFileSystemObject?
    private var lastWritten: Data?

    /// Re-arms when the file is replaced: a directory watch misses in-place
    /// overwrites, a file watch is stranded by an atomic save.
    func watchForExternalEdits() {
        watcher?.cancel()

        let descriptor = open(fileURL.path, O_EVTONLY)
        guard descriptor >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .extend, .delete, .rename],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            let replaced = source.data.contains(.delete) || source.data.contains(.rename)

            MainActor.assumeIsolated {
                guard let self else { return }

                self.reloadIfChangedOnDisk()
                // Re-arming here would cancel the running source.
                if replaced {
                    DispatchQueue.main.async { self.watchForExternalEdits() }
                }
            }
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()

        watcher = source
    }

    /// Content, not timestamps: every save is a write and would loop.
    private func reloadIfChangedOnDisk() {
        guard let data = try? Data(contentsOf: fileURL), data != lastWritten,
              let config = try? JSONDecoder().decode(Config.self, from: data)
        else { return }

        log.notice("config.json changed on disk, reloading \(config.bindings.count, privacy: .public) bindings")
        lastWritten = data
        apply(config)
        onChange?()
    }

    private func commit() {
        save()
        onChange?()
    }

    // MARK: - Editing bindings

    func add() {
        bindings.append(AppBinding(key: "", bundleID: ""))
        commit()
    }

    func remove(_ id: UUID) {
        bindings.removeAll { $0.id == id }
        commit()
    }

    func key(for id: UUID) -> String {
        bindings.first { $0.id == id }?.key ?? ""
    }

    func setKey(_ key: String, for id: UUID) {
        guard let index = bindings.firstIndex(where: { $0.id == id }) else { return }

        // Longer input is only meaningful for named keys like F1.
        bindings[index].key = key.count == 1 ? key.lowercased() : key
        commit()
    }

    func setBundleID(_ bundleID: String, for id: UUID) {
        guard let index = bindings.firstIndex(where: { $0.id == id }) else { return }

        bindings[index].bundleID = bundleID
        commit()
    }

    func setUsesLeader(_ usesLeader: Bool, for id: UUID) {
        guard let index = bindings.firstIndex(where: { $0.id == id }) else { return }

        bindings[index].usesLeader = usesLeader
        commit()
    }

    // MARK: - Editing exclusions

    func excluding(_ bundleID: String) {
        guard !settings.excludedBundleIDs.contains(bundleID) else { return }

        settings.excludedBundleIDs.append(bundleID)
    }

    func stopExcluding(_ bundleID: String) {
        settings.excludedBundleIDs.removeAll { $0 == bundleID }
    }

    // MARK: - Problems worth showing

    enum Issue: Equatable {
        case noApplication
        case unknownKey
        case duplicate
        case shadowsCharacter(Character)
        case takenByWindowAction(String)

        var message: String {
            switch self {
            case .noApplication: return "Pick an application"
            case .unknownKey: return "No key produces this on the current layout"
            case .duplicate: return "Another binding already uses this key"
            case .shadowsCharacter(let character):
                return "Option-this types \(character), which this binding takes away everywhere"
            case .takenByWindowAction(let name):
                return "\(name) already uses your leader with this key, and wins"
            }
        }
    }

    /// The router matches window actions before bindings, so a leader that
    /// collides with one leaves the binding unreachable. That is the case here.
    func issue(
        for binding: AppBinding,
        leader: CGEventFlags = [],
        navigation: ModifierChoice = .optionControl,
        displayMove: DisplayMoveModifier = .shiftOption
    ) -> Issue? {
        if binding.bundleID.isEmpty { return .noApplication }
        guard let code = KeyboardLayout.keyCode(forBinding: binding.key), !binding.key.isEmpty else {
            return .unknownKey
        }
        if bindings.contains(where: { $0.id != binding.id && $0.key == binding.key && $0.usesLeader == binding.usesLeader }) {
            return .duplicate
        }
        if binding.usesLeader,
           let action = WindowArrangement.matching(
               keyCode: code, modifiers: leader,
               navigation: navigation, displayMove: displayMove
           ) {
            let name = WindowArrangement.shortcuts(navigation: navigation, displayMove: displayMove)
                .first { $0.arrangement == action }?.name ?? "a window action"

            return .takenByWindowAction(name)
        }
        if binding.usesLeader, binding.key.count == 1, let character = binding.key.first,
           let shadowed = KeyboardLayout.asciiOptionCharacter(for: character)
        {
            return .shadowsCharacter(shadowed)
        }

        return nil
    }
}
