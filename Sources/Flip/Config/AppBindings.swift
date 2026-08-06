import Carbon.HIToolbox
import CoreGraphics

enum AppBindings {
    /// Keyed by bundle ID rather than by name, because name lookups are ambiguous:
    /// "Cursor" also matches a macOS text input service, and "Google Chrome" also
    /// matches "Google Chrome Dev".
    ///
    /// Written as characters, not key codes: which physical key produces "z"
    /// depends on the keyboard layout, and KeyboardLayout resolves that.
    static let byCharacter: [Character: String] = [
        "c": "com.tinyspeck.slackmacgap",                              // Slack
        "e": "com.todesktop.230313mzl4w4u92",                          // Cursor
        "f": "org.yanex.marta",                                        // Marta
        "g": "com.google.Chrome.app.kjgfgldnnfoeklkmfkjfagphfepbbdan", // Google Meet
        "i": "com.jetbrains.intellij",                                 // IntelliJ IDEA
        "j": "dev.zed.Zed",                                            // Zed
        "o": "md.obsidian",                                            // Obsidian
        "q": "org.whispersystems.signal-desktop",                      // Signal
        "s": "com.spotify.client",                                     // Spotify
        "t": "com.mitchellh.ghostty",                                  // Ghostty
        "w": "com.microsoft.teams2",                                   // Microsoft Teams
        "1": "com.google.Chrome",                                      // Google Chrome
        "2": "com.google.Chrome.dev",                                  // Google Chrome Dev
    ]

    /// Reached without any modifier, so these really do take the key away from
    /// every application: F1 no longer opens help, and no longer shows quick
    /// documentation in IntelliJ. Function keys sit at fixed codes regardless of
    /// layout, so they need no translation.
    static let byKeyCode: [CGKeyCode: String] = [
        CGKeyCode(kVK_F1): "com.mitchellh.ghostty",
    ]
}
