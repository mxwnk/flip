import CoreGraphics
import Foundation
import OSLog
import ScreenCaptureKit

/// Window thumbnails, captured through ScreenCaptureKit.
///
/// This is where the Lua switcher spent most of its time: a capture cost about
/// 14 ms, they ran one per runloop tick on the main thread, and fifteen windows
/// meant roughly 210 ms of half-empty grid competing with keystroke handling.
///
/// Here they are all requested at once, scaled down by the GPU during capture
/// rather than held at full resolution afterwards, and delivered as they land.
final class ThumbnailStore: @unchecked Sendable {
    /// Matches the Lua switcher's thumbnail size, so the tiles look the same.
    private static let target = CGSize(width: 600, height: 348)

    /// How old an image may be before it is captured again. Note that it is still
    /// shown in the meantime.
    private static let refreshAfter: TimeInterval = 30

    /// How old before it is dropped altogether. At roughly 800 KB apiece this only
    /// bounds windows that have not been seen in a long while.
    private static let discardAfter: TimeInterval = 300

    private let log = Logger(subsystem: Bundle.identifier, category: "thumbnails")
    private let sources = ShareableWindows()

    private let lock = NSLock()
    private var images: [CGWindowID: (image: CGImage, at: Date)] = [:]

    /// Instant and synchronous: what the overlay can draw the moment it opens.
    ///
    /// Deliberately ignores age. A thumbnail from a minute ago still shows which
    /// window this is, and dropping back to an application icon for the 150 ms it
    /// takes to capture a fresh one is a worse picture, not a more honest one.
    func cached(_ id: CGWindowID) -> CGImage? {
        lock.lock()
        defer { lock.unlock() }

        return images[id]?.image
    }

    private func needsCapture(_ id: CGWindowID) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        guard let entry = images[id] else { return true }

        return Date().timeIntervalSince(entry.at) >= Self.refreshAfter
    }

    /// Captures everything not already cached, all at once. The callback runs on
    /// the main actor once per image, as it arrives, so the grid fills in rather
    /// than waiting for the slowest window.
    ///
    /// The first identifier should be the selected tile: it is the one being
    /// looked at, so it gets its request in first.
    func fill(_ ids: [CGWindowID], onImage: @escaping @MainActor (CGWindowID, CGImage) -> Void) {
        let missing = ids.filter(needsCapture)
        guard !missing.isEmpty else { return }

        Task.detached(priority: .userInitiated) { [self] in
            let started = DispatchTime.now().uptimeNanoseconds

            await withTaskGroup(of: Void.self) { group in
                for id in missing {
                    group.addTask { [self] in
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

    /// Warms the cache away from the critical path. A window losing focus is the
    /// ideal moment: its content is final, it is still on screen, and nobody is
    /// waiting on the result.
    func warm(_ ids: [CGWindowID]) {
        fill(ids) { _, _ in }
    }

    private func store(_ image: CGImage, for id: CGWindowID) {
        lock.lock()
        images[id] = (image, Date())

        // Sweep on write, so captures of long gone windows do not accumulate for
        // the lifetime of the process.
        let now = Date()
        images = images.filter { now.timeIntervalSince($0.value.at) < Self.discardAfter }
        lock.unlock()
    }

    private func capture(_ id: CGWindowID) async -> CGImage? {
        guard let window = await sources.window(for: id) else { return nil }

        let filter = SCContentFilter(desktopIndependentWindow: window)
        let rect = filter.contentRect
        guard rect.width > 0, rect.height > 0 else { return nil }

        let configuration = SCStreamConfiguration()
        // Scaled while capturing, on the GPU. The Lua version kept full resolution
        // images and only set a display size, which is why its cache was heavy for
        // no benefit.
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
            log.debug("  capture \(id, privacy: .public): \(String(format: "%.1f", elapsed), privacy: .public)ms")

            return image
        } catch {
            // Windows disappear between being listed and being captured; that is
            // ordinary, and the tile simply keeps its icon.
            log.debug("no capture for \(id, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}

/// The ScreenCaptureKit view of what can be captured.
///
/// Enumerating it costs around 60 ms — more than a capture — so the listing is
/// held onto rather than fetched per window.
private actor ShareableWindows {
    /// An SCWindow stays usable for as long as its window exists, so this only
    /// bounds how long a *missing* entry can be believed. A window that is not in
    /// the listing forces a refresh regardless of age, which is what covers
    /// windows opened since the last one.
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

    /// Actors are reentrant: awaiting inside one lets every other caller in, and
    /// they all arrive before the first has anything to show for itself. Without
    /// joining a refresh that is already running, a grid of five tiles fetched the
    /// listing five times over — measured at 59, 75, 93, 113 and 132 ms as they
    /// piled up behind each other.
    private func refresh() async {
        if let inFlight { return await inFlight.value }

        // Assigned before the first await, so no other caller can slip past it.
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
