import AppKit
import Foundation
import OSLog

/// Asks GitHub what the newest release is, and stops. Nothing is downloaded, so
/// updating stays deliberate and Homebrew keeps owning the copy it installed.
@MainActor
final class UpdateChecker {
    static let releases = URL(string: "https://github.com/mxwnk/flip/releases/latest")!
    private static let latest = URL(string: "https://api.github.com/repos/mxwnk/flip/releases/latest")!

    private let log = Logger(subsystem: Bundle.identifier, category: "updates")
    private let settings: SettingsStore
    private var daily: Timer?

    /// Only when genuinely newer, so a development copy running ahead of the
    /// last release stays quiet.
    private(set) var available: String?
    var onFound: (() -> Void)?

    init(settings: SettingsStore) {
        self.settings = settings
    }

    func start() {
        // Not at launch: at login the network is usually not up yet.
        Timer.scheduledTimer(withTimeInterval: 30, repeats: false) { _ in
            MainActor.assumeIsolated { [weak self] in self?.check() }
        }
        daily = Timer.scheduledTimer(withTimeInterval: 24 * 60 * 60, repeats: true) { _ in
            MainActor.assumeIsolated { [weak self] in self?.check() }
        }
    }

    func check() {
        guard settings.settings.checkForUpdates else { return }

        Task { await ask() }
    }

    /// Dot-separated numbers, not strings, where 0.10.0 sorts below 0.9.0.
    nonisolated static func isNewer(_ candidate: String, than current: String) -> Bool {
        let new = numbers(in: candidate)
        let old = numbers(in: current)

        for index in 0..<max(new.count, old.count) {
            let left = index < new.count ? new[index] : 0
            let right = index < old.count ? old[index] : 0
            if left != right { return left > right }
        }

        return false
    }

    /// Tolerates a tag's leading v; anything unparseable becomes zero, so a
    /// malformed tag cannot look like an upgrade.
    nonisolated static func numbers(in version: String) -> [Int] {
        version
            .drop { !$0.isNumber }
            .split(separator: ".")
            .map { Int($0.prefix { $0.isNumber }) ?? 0 }
    }

    private struct Release: Decodable {
        let tagName: String

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
        }
    }

    private func ask() async {
        var request = URLRequest(url: Self.latest)
        // GitHub answers anonymous requests with 403 unless one is set.
        request.setValue("Flip/\(Bundle.main.shortVersion)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let status = (response as? HTTPURLResponse)?.statusCode, status == 200 else {
                log.debug("update check answered \((response as? HTTPURLResponse)?.statusCode ?? -1, privacy: .public)")
                return
            }

            let tag = try JSONDecoder().decode(Release.self, from: data).tagName
            let current = Bundle.main.shortVersion
            guard Self.isNewer(tag, than: current) else {
                log.debug("\(current, privacy: .public) is current; newest is \(tag, privacy: .public)")
                return
            }

            let version = String(tag.drop { !$0.isNumber })
            guard version != available else { return }

            available = version
            log.notice("\(version, privacy: .public) is available")
            onFound?()
        } catch {
            // Offline is the normal case here, not a fault worth reporting.
            log.debug("update check failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
