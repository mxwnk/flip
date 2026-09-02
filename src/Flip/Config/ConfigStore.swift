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

    var bindings: [AppBinding] { settings.shortcuts.bindings }

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
            log.notice("no config file yet, writing the defaults")
            apply(Settings())
            save()
            return
        }

        do {
            apply(try JSONDecoder().decode(Settings.self, from: data))
            log.notice("loaded \(self.bindings.count, privacy: .public) bindings")
        } catch {
            // Defaults beat no hotkeys; the broken file is left for inspection.
            log.error("config unreadable (\(error.localizedDescription, privacy: .public)), using defaults")
            apply(Settings())
        }
    }

    private var isApplying = false

    /// Loading is not editing: the save the assignment would otherwise trigger
    /// would only write back what was just read.
    private func apply(_ loaded: Settings) {
        isApplying = true
        settings = loaded
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
            let data = try encoder.encode(settings)
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
              let loaded = try? JSONDecoder().decode(Settings.self, from: data)
        else { return }

        let count = loaded.shortcuts.bindings.count
        log.notice("config.json changed on disk, reloading \(count, privacy: .public) bindings")
        lastWritten = data
        apply(loaded)
        onChange?()
    }

    private func commit() {
        save()
        onChange?()
    }

    // MARK: - Editing bindings

    func add() {
        settings.shortcuts.bindings.append(AppBinding(key: "", bundleID: ""))
    }

    func remove(_ id: UUID) {
        settings.shortcuts.bindings.removeAll { $0.id == id }
    }

    func key(for id: UUID) -> String {
        bindings.first { $0.id == id }?.key ?? ""
    }

    func setKey(_ key: String, for id: UUID) {
        guard let index = index(of: id) else { return }

        // Longer input is only meaningful for named keys like F1.
        settings.shortcuts.bindings[index].key = key.count == 1 ? key.lowercased() : key
    }

    func setBundleID(_ bundleID: String, for id: UUID) {
        guard let index = index(of: id) else { return }

        settings.shortcuts.bindings[index].bundleID = bundleID
    }

    func setUsesLeader(_ usesLeader: Bool, for id: UUID) {
        guard let index = index(of: id) else { return }

        settings.shortcuts.bindings[index].usesLeader = usesLeader
    }

    private func index(of id: UUID) -> Int? {
        bindings.firstIndex { $0.id == id }
    }

    // MARK: - Editing exclusions

    func excluding(_ bundleID: String) {
        guard !settings.excluded.contains(bundleID) else { return }

        settings.excluded.append(bundleID)
    }

    func stopExcluding(_ bundleID: String) {
        settings.excluded.removeAll { $0 == bundleID }
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
        arrangeLeader: ModifierChoice = .optionControl,
        displayMove: DisplayMoveModifier = .shiftOption,
        arrangeKeys: [WindowArrangement: String] = WindowArrangement.defaultKeys
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
               leader: arrangeLeader, displayMove: displayMove, keys: arrangeKeys
           ) {
            let name = WindowArrangement
                .shortcuts(leader: arrangeLeader, displayMove: displayMove, keys: arrangeKeys)
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
