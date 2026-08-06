/// What a fresh install starts with. Everything after that lives in
/// `bindings.json` and is edited from the menu bar, so this is a seed rather than
/// the configuration.
enum DefaultBindings {
    /// Keyed by bundle ID rather than by name, because name lookups are ambiguous:
    /// "Cursor" also matches a macOS text input service, and "Google Chrome" also
    /// matches "Google Chrome Dev".
    static let all: [AppBinding] = [
        AppBinding(key: "c", bundleID: "com.tinyspeck.slackmacgap"),
        AppBinding(key: "e", bundleID: "com.todesktop.230313mzl4w4u92"), // Cursor
        AppBinding(key: "f", bundleID: "org.yanex.marta"),
        AppBinding(key: "g", bundleID: "com.google.Chrome.app.kjgfgldnnfoeklkmfkjfagphfepbbdan"), // Meet
        AppBinding(key: "i", bundleID: "com.jetbrains.intellij"),
        AppBinding(key: "j", bundleID: "dev.zed.Zed"),
        AppBinding(key: "o", bundleID: "md.obsidian"),
        AppBinding(key: "q", bundleID: "org.whispersystems.signal-desktop"),
        AppBinding(key: "s", bundleID: "com.spotify.client"),
        AppBinding(key: "t", bundleID: "com.mitchellh.ghostty"),
        AppBinding(key: "w", bundleID: "com.microsoft.teams2"),
        AppBinding(key: "1", bundleID: "com.google.Chrome"),
        AppBinding(key: "2", bundleID: "com.google.Chrome.dev"),
        AppBinding(key: "F1", bundleID: "com.mitchellh.ghostty", usesLeader: false),
    ]
}
