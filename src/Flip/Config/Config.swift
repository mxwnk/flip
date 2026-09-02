import Foundation

/// The whole configuration as one document: every setting the settings window
/// can change, plus the bindings. Flat rather than nested, so a hand edit reads
/// the same as the settings window: one key per setting.
struct Config: Codable {
    var settings: Settings
    var bindings: [AppBinding]

    init(settings: Settings = Settings(), bindings: [AppBinding] = DefaultBindings.all) {
        self.settings = settings
        self.bindings = bindings
    }

    private enum CodingKeys: String, CodingKey {
        case bindings
    }

    init(from decoder: Decoder) throws {
        settings = try Settings(from: decoder)
        bindings = try decoder.container(keyedBy: CodingKeys.self)
            .decodeIfPresent([AppBinding].self, forKey: .bindings) ?? DefaultBindings.all
    }

    /// Both halves into the same keyed container, which is what makes the file
    /// flat: the settings write their own keys, this adds one more.
    func encode(to encoder: Encoder) throws {
        try settings.encode(to: encoder)

        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(bindings, forKey: .bindings)
    }
}
