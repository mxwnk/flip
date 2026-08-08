import CoreGraphics
import Foundation
import OSLog
import ScreenCaptureKit

/// Window thumbnails, captured concurrently and scaled by the GPU during capture.
final class ThumbnailStore: @unchecked Sendable {
    /// Twice the tile, for retina. Derived rather than written out, so a tile
    /// that grows past a stale target cannot go soft.
    private static let target = CGSize(
        width: Theme.tileWidth * 2,
        height: (Theme.tileWidth * Theme.thumbnailRatio).rounded(.down) * 2
    )

    /// The size accessibility reports, which Stage Manager does not distort.
    var expectedSize: (@Sendable (CGWindowID) -> CGSize?)?

    /// Below this a capture is a Stage Manager miniature, not a window: the
    /// parked strip is ~200 points wide, a real window is not.
    private static let smallestRealWindow: CGFloat = 400

    /// Still shown while stale; only capture is triggered.
    private static let refreshAfter: TimeInterval = 30

    private static let discardAfter: TimeInterval = 300

    private let log = Logger(subsystem: Bundle.identifier, category: "thumbnails")
    private let sources = ShareableWindows()

    private let lock = NSLock()
    private var images: [CGWindowID: (image: CGImage, at: Date)] = [:]
    /// Captures already on their way. Without this, `needsCapture` only ever
    /// saw finished ones, so two fills a moment apart — the overlay revealing
    /// itself and then narrowing — sent every window through twice.
    private var inFlight: Set<CGWindowID> = []

    /// Ignores age: an icon for the ~150ms of a fresh capture looks worse than
    /// a slightly stale thumbnail.
    func cached(_ id: CGWindowID) -> CGImage? {
        lock.lock()
        defer { lock.unlock() }

        return images[id]?.image
    }

    /// Takes the ids that nobody else is already capturing, in one step, so two
    /// callers cannot both come away believing they own the same window.
    private func claim(_ ids: [CGWindowID]) -> [CGWindowID] {
        lock.lock()
        defer { lock.unlock() }

        let free = ids.filter { !inFlight.contains($0) }
        inFlight.formUnion(free)

        return free
    }

    private func release(_ id: CGWindowID) {
        lock.lock()
        inFlight.remove(id)
        lock.unlock()
    }

    private func needsCapture(_ id: CGWindowID) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        guard let entry = images[id] else { return true }

        return Date().timeIntervalSince(entry.at) >= Self.refreshAfter
    }

    /// Calls back per image as it lands. Pass the selected tile first.
    func fill(_ ids: [CGWindowID], onImage: @escaping @MainActor (CGWindowID, CGImage) -> Void) {
        let missing = claim(ids.filter(needsCapture))
        guard !missing.isEmpty else { return }

        Task.detached(priority: .userInitiated) { [self] in
            let started = DispatchTime.now().uptimeNanoseconds

            await withTaskGroup(of: Void.self) { group in
                for id in missing {
                    group.addTask { [self] in
                        defer { release(id) }
                        guard let image = await capture(id) else { return }

                        store(image, for: id)
                        await MainActor.run { onImage(id, image) }
                    }
                }
            }

            let elapsed = Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000
            log.debug("""
            captured \(missing.count, privacy: .public) windows \
            in \(String(format: "%.1f", elapsed), privacy: .public)ms
            """)
        }
    }

    func warm(_ ids: [CGWindowID]) {
        fill(ids) { _, _ in }
    }

    private func store(_ image: CGImage, for id: CGWindowID) {
        lock.lock()
        images[id] = (image, Date())

        let now = Date()
        images = images.filter { now.timeIntervalSince($0.value.at) < Self.discardAfter }
        lock.unlock()
    }

    private func capture(_ id: CGWindowID) async -> CGImage? {
        guard let window = await sources.window(for: id) else { return nil }

        let filter = SCContentFilter(desktopIndependentWindow: window)
        let rect = filter.contentRect
        guard rect.width > 0, rect.height > 0 else { return nil }

        // Stage Manager parks a window as a tilted miniature and the window
        // server reports that as the window. Accessibility keeps reporting the
        // real size, so the two disagreeing is the tell — measured 200 against
        // 2497. Returning nothing keeps the capture from before it was parked.
        if rect.width < Self.smallestRealWindow,
           let expected = expectedSize?(id), expected.width > 0,
           rect.width < expected.width / 2 {
            log.debug("parked \(id, privacy: .public): \(Int(rect.width), privacy: .public) wide, accessibility says \(Int(expected.width), privacy: .public)")
            return nil
        }

        let configuration = SCStreamConfiguration()
        let scale = min(Self.target.width / rect.width, Self.target.height / rect.height, 1)
        configuration.width = Int(rect.width * scale)
        configuration.height = Int(rect.height * scale)
        configuration.showsCursor = false

        do {
            let started = DispatchTime.now().uptimeNanoseconds
            let image = try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: configuration
            )
            let elapsed = Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000
            log.debug("""
              capture \(id, privacy: .public): \
            \(String(format: "%.1f", elapsed), privacy: .public)ms \
            rect \(Int(rect.width), privacy: .public)x\(Int(rect.height), privacy: .public) \
            asked \(configuration.width, privacy: .public)x\(configuration.height, privacy: .public) \
            got \(image.width, privacy: .public)x\(image.height, privacy: .public)
            """)

            return image
        } catch {
            // Windows disappear between listing and capture; the tile keeps its icon.
            log.debug("no capture for \(id, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}

/// Enumerating shareable content costs ~60ms, more than a capture, so the
/// listing is held rather than fetched per window.
private actor ShareableWindows {
    /// An SCWindow stays valid while its window exists, so this only bounds how
    /// long a *missing* entry is believed.
    private static let lifetime: TimeInterval = 60

    private let log = Logger(subsystem: Bundle.identifier, category: "thumbnails")

    private var byID: [CGWindowID: SCWindow] = [:]
    private var fetchedAt: Date?
    private var inFlight: Task<Void, Never>?

    func window(for id: CGWindowID) async -> SCWindow? {
        if isFresh, let window = byID[id] { return window }

        await refresh()

        return byID[id]
    }

    private var isFresh: Bool {
        guard let fetchedAt else { return false }

        return Date().timeIntervalSince(fetchedAt) < Self.lifetime
    }

    /// Actors are reentrant: without joining a refresh in flight, five concurrent
    /// tiles fetched the listing five times, serialised to 132ms. Assigned before
    /// the first await so no caller slips past.
    private func refresh() async {
        if let inFlight { return await inFlight.value }

        let task = Task { await fetch() }
        inFlight = task
        await task.value
        inFlight = nil
    }

    private func fetch() async {
        let started = DispatchTime.now().uptimeNanoseconds

        guard let content = try? await SCShareableContent.excludingDesktopWindows(
            true,
            onScreenWindowsOnly: false
        ) else { return }

        var resolved: [CGWindowID: SCWindow] = [:]
        for window in content.windows {
            resolved[window.windowID] = window
        }

        byID = resolved
        fetchedAt = Date()

        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000
        log.debug("listed \(resolved.count, privacy: .public) shareable windows in \(String(format: "%.1f", elapsed), privacy: .public)ms")
    }
}
