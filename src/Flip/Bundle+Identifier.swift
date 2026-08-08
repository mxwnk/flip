import Foundation

extension Bundle {
    /// The bundle identifier, falling back for a run straight out of `.build`.
    /// It is the os_log subsystem, so `make logs` works either way.
    static let identifier = Bundle.main.bundleIdentifier ?? "dev.mxwnk.Flip"
}
