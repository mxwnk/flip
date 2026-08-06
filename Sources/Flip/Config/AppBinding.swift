import Foundation

/// One key bound to one application.
struct AppBinding: Identifiable, Equatable, Codable {
    /// Only for SwiftUI list identity. Deliberately not persisted: the file is
    /// meant to be readable and hand-editable, and a UUID in it is noise. Rows
    /// are identified by key everywhere else, and a key can be empty or duplicated
    /// mid-edit, which is exactly when a stable identity is needed.
    let id: UUID

    /// A single character, resolved against the current keyboard layout, or a
    /// named key such as "F1" for the ones no character can express.
    var key: String

    var bundleID: String

    /// False for keys that reach an application with no modifier at all. Those are
    /// taken away from every application, so F1 no longer opens help anywhere.
    var usesLeader: Bool

    init(key: String, bundleID: String, usesLeader: Bool = true) {
        self.id = UUID()
        self.key = key
        self.bundleID = bundleID
        self.usesLeader = usesLeader
    }

    private enum CodingKeys: String, CodingKey {
        case key, bundleID, usesLeader
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = UUID()
        key = try container.decode(String.self, forKey: .key)
        bundleID = try container.decode(String.self, forKey: .bundleID)
        usesLeader = try container.decodeIfPresent(Bool.self, forKey: .usesLeader) ?? true
    }
}
