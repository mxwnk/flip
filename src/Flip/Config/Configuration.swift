import Foundation

/// Constants that are not worth a setting — the kind of value that only ever
/// changes with a code change. Anything a user edits lives in `Settings`.
enum Configuration {
    /// A last resort against a stuck modifier leaving the overlay up for good.
    static let maxOverlayLifetime: TimeInterval = 30
}
