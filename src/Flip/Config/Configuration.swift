import Foundation

/// Constants that are not worth a setting.
///
/// The hotkeys, thumbnails and exclusions moved to `Settings`, which is written to
/// disk and edited from the menu bar. What is left here is the kind of value that
/// only ever changes with a code change.
enum Configuration {
    /// How long the overlay may stay up without a modifier release ever arriving.
    /// A last resort against a stuck modifier leaving it on screen for good.
    static let maxOverlayLifetime: TimeInterval = 30
}
