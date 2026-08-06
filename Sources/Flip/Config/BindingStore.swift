import Foundation
import OSLog

/// The bindings, and the file they live in.
///
/// Kept as readable JSON in Application Support rather than in UserDefaults, so
/// it can be inspected, diffed and carried between machines like the rest of a
/// dotfiles setup.
@MainActor
final class BindingStore: ObservableObject {
    @Published private(set) var bindings: [AppBinding] = []

    /// Called after every change, once the file is written. The key router
    /// rebuilds from this.
    var onChange: (() -> Void)?

    private let log = Logger(subsystem: Bundle.identifier, category: "bindings")

    private static let file = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Flip", isDirectory: true)
        .appendingPathComponent("bindings.json")

    var fileURL: URL { Self.file }

    // MARK: - Loading and saving

    func load() {
        guard let data = try? Data(contentsOf: Self.file) else {
            log.notice("no bindings file yet, seeding from the defaults")
            bindings = DefaultBindings.all
            save()
            return
        }

        do {
            bindings = try JSONDecoder().decode([AppBinding].self, from: data)
            log.notice("loaded \(self.bindings.count, privacy: .public) bindings")
        } catch {
            // Better to keep working with the defaults than to start with no
            // hotkeys at all; the broken file is left alone for inspection.
            log.error("bindings file unreadable (\(error.localizedDescription, privacy: .public)), using defaults")
            bindings = DefaultBindings.all
        }
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]

        do {
            try FileManager.default.createDirectory(
                at: Self.file.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try encoder.encode(bindings)
            try data.write(to: Self.file, options: .atomic)
            lastWritten = data
        } catch {
            log.error("could not save bindings: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Noticing edits made by hand

    private var watcher: DispatchSourceFileSystemObject?
    private var lastWritten: Data?

    /// Watches the file itself, and re-arms when it is replaced.
    ///
    /// Watching the containing directory instead looks tempting, because an atomic
    /// save swaps the inode and leaves a file-level watch pointing at something
    /// unreachable. But a directory only reports entries appearing and
    /// disappearing — an editor that overwrites in place changes nothing about the
    /// directory, and that edit goes unnoticed. Both kinds have to be covered, so
    /// the file is watched and the watch is rebuilt whenever the inode goes away.
    func watchForExternalEdits() {
        watcher?.cancel()

        let descriptor = open(Self.file.path, O_EVTONLY)
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
                // Re-arming inside the handler would cancel the source that is
                // running, so it waits for the next turn of the runloop.
                if replaced {
                    DispatchQueue.main.async { self.watchForExternalEdits() }
                }
            }
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()

        watcher = source
    }

    /// Comparing content rather than timestamps is what keeps this from looping:
    /// every save is itself a directory write, and reacting to those would reload,
    /// re-save and start again.
    private func reloadIfChangedOnDisk() {
        guard let data = try? Data(contentsOf: Self.file), data != lastWritten,
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

        // A single character is what the field is for; longer input is only
        // meaningful for named keys like F1, which are matched case-insensitively.
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
        /// Binding this key takes a character away from every application.
        case shadowsCharacter(Character)

        var message: String {
            switch self {
            case .noApplication: return "Pick an application"
            case .unknownKey: return "No key produces this on the current layout"
            case .duplicate: return "Another binding already uses this key"
            case .shadowsCharacter(let character):
                return "Option-this types \(character), which this binding takes away everywhere"
            }
        }
    }

    func issue(for binding: AppBinding) -> Issue? {
        if binding.bundleID.isEmpty { return .noApplication }
        if binding.key.isEmpty || KeyboardLayout.keyCode(forBinding: binding.key) == nil {
            return .unknownKey
        }
        if bindings.contains(where: { $0.id != binding.id && $0.key == binding.key && $0.usesLeader == binding.usesLeader }) {
            return .duplicate
        }
        if binding.usesLeader, binding.key.count == 1, let character = binding.key.first,
           let shadowed = KeyboardLayout.asciiOptionCharacter(for: character)
        {
            return .shadowsCharacter(shadowed)
        }

        return nil
    }
}
