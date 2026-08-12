import CoreGraphics
import Foundation
import OSLog

/// The bindings, as readable JSON in Application Support: inspectable, diffable,
/// portable between machines.
@MainActor
final class BindingStore: ObservableObject {
    @Published private(set) var bindings: [AppBinding] = []

    var onChange: (() -> Void)?

    /// Raised while the settings window waits for a key. Flip's own tap would
    /// otherwise swallow one already bound bare, F1 above all.
    var onKeyCapture: ((Bool) -> Void)?

    private let log = Logger(subsystem: Bundle.identifier, category: "bindings")

    /// Injectable so tests cannot write over the real configuration.
    let fileURL: URL

    init(file: URL = ApplicationSupport.file("bindings.json")) {
        self.fileURL = file
    }

    // MARK: - Loading and saving

    func load() {
        guard let data = try? Data(contentsOf: fileURL) else {
            log.notice("no bindings file yet, seeding from the defaults")
            bindings = DefaultBindings.all
            save()
            return
        }

        do {
            bindings = try JSONDecoder().decode([AppBinding].self, from: data)
            log.notice("loaded \(self.bindings.count, privacy: .public) bindings")
        } catch {
            // Defaults beat no hotkeys; the broken file is left for inspection.
            log.error("bindings file unreadable (\(error.localizedDescription, privacy: .public)), using defaults")
            bindings = DefaultBindings.all
        }
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]

        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try encoder.encode(bindings)
            try data.write(to: fileURL, options: .atomic)
            lastWritten = data
        } catch {
            log.error("could not save bindings: \(error.localizedDescription, privacy: .public)")
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
              let decoded = try? JSONDecoder().decode([AppBinding].self, from: data)
        else { return }

        log.notice("bindings.json changed on disk, reloading \(decoded.count, privacy: .public) bindings")
        lastWritten = data
        bindings = decoded
        onChange?()
    }

    private func commit() {
        save()
        onChange?()
    }

    // MARK: - Editing

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
