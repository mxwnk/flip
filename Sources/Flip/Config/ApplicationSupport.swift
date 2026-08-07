import Foundation

enum ApplicationSupport {
    static func file(_ name: String) -> URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Flip", isDirectory: true)
            .appendingPathComponent(name)
    }
}
