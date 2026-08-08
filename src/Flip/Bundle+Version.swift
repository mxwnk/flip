import Foundation

extension Bundle {
    var shortVersion: String {
        object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    var build: String {
        object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "dev"
    }

    /// The build number only shows when it differs from the version; the
    /// Makefile currently writes the same value into both.
    var versionDescription: String {
        build == shortVersion ? shortVersion : "\(shortVersion) (\(build))"
    }

    /// The Makefile writes it into Info.plist so the year lives in one place.
    var copyright: String {
        object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String ?? ""
    }
}
