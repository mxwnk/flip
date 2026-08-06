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
            try encoder.encode(bindings).write(to: Self.file, options: .atomic)
        } catch {
            log.error("could not save bindings: \(error.localizedDescription, privacy: .public)")
        }
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
