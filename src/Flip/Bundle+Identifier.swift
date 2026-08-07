import Foundation

extension Bundle {
    /// The bundle identifier, with a fallback for the case where the executable
    /// is run straight out of `.build` rather than from the assembled app. Used
    /// as the os_log subsystem, so `make logs` keeps working either way.
    static let identifier = Bundle.main.bundleIdentifier ?? "dev.mxwnk.Flip"
}
