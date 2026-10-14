import XCTest

@testable import Flip

final class SecureInputEpisodeTests: XCTestCase {
    private let start = Date(timeIntervalSinceReferenceDate: 0)

    private func later(_ seconds: TimeInterval) -> Date {
        start.addingTimeInterval(seconds)
    }

    func testTurningOnStartsAnEpisode() {
        var episode = SecureInputEpisode()

        XCTAssertEqual(episode.observe(isOn: true, at: start), .started)
        XCTAssertTrue(episode.isOn)
    }

    /// A password field being typed into is no reason to interrupt anyone.
    func testABriefEpisodeIsNotExplained() {
        var episode = SecureInputEpisode()
        _ = episode.observe(isOn: true, at: start)

        XCTAssertEqual(episode.observe(isOn: true, at: later(SecureInputEpisode.patience - 1)), .none)
        XCTAssertEqual(episode.observe(isOn: false, at: later(SecureInputEpisode.patience - 0.5)), .ended)
    }

    func testALongEpisodeIsExplainedOnce() {
        var episode = SecureInputEpisode()
        _ = episode.observe(isOn: true, at: start)

        XCTAssertEqual(episode.observe(isOn: true, at: later(SecureInputEpisode.patience)), .needsExplaining)
        XCTAssertEqual(episode.observe(isOn: true, at: later(SecureInputEpisode.patience + 30)), .none)
    }

    func testTheNextEpisodeIsExplainedAgain() {
        var episode = SecureInputEpisode()
        _ = episode.observe(isOn: true, at: start)
        _ = episode.observe(isOn: true, at: later(SecureInputEpisode.patience))
        _ = episode.observe(isOn: false, at: later(20))

        _ = episode.observe(isOn: true, at: later(30))

        XCTAssertEqual(episode.observe(isOn: true, at: later(30 + SecureInputEpisode.patience)), .needsExplaining)
    }

    func testStayingOffChangesNothing() {
        var episode = SecureInputEpisode()

        XCTAssertEqual(episode.observe(isOn: false, at: start), .none)
        XCTAssertFalse(episode.isOn)
    }
}

/// The lock screen holds secure input for as long as it is up, which is no
/// reason to greet whoever unlocks it with a warning.
final class SecureInputLockScreenTests: XCTestCase {
    private let start = Date(timeIntervalSinceReferenceDate: 0)
    private let patience = SecureInputEpisode.patience

    private func later(_ seconds: TimeInterval) -> Date {
        start.addingTimeInterval(seconds)
    }

    func testALockedScreenIsNeverExplained() {
        var episode = SecureInputEpisode()
        _ = episode.observe(isOn: true, isScreenLocked: true, at: start)

        XCTAssertEqual(episode.observe(isOn: true, isScreenLocked: true, at: later(patience * 20)), .none)
    }

    func testUnlockingThatReleasesSecureInputEndsTheEpisodeQuietly() {
        var episode = SecureInputEpisode()
        _ = episode.observe(isOn: true, isScreenLocked: true, at: start)
        _ = episode.observe(isOn: true, isScreenLocked: true, at: later(600))

        XCTAssertEqual(episode.observe(isOn: false, isScreenLocked: false, at: later(602)), .ended)
    }

    /// Patience starts over at the unlock, not at the lock.
    func testSecureInputLeftOnAfterUnlockingIsExplainedOnlyAfterPatience() {
        var episode = SecureInputEpisode()
        _ = episode.observe(isOn: true, isScreenLocked: true, at: start)
        _ = episode.observe(isOn: true, isScreenLocked: true, at: later(600))

        XCTAssertEqual(episode.observe(isOn: true, isScreenLocked: false, at: later(602)), .none)
        XCTAssertEqual(episode.observe(isOn: true, isScreenLocked: false, at: later(600 + patience)), .needsExplaining)
    }

    func testLockingMidwayPostponesTheExplanation() {
        var episode = SecureInputEpisode()
        _ = episode.observe(isOn: true, at: start)
        _ = episode.observe(isOn: true, isScreenLocked: true, at: later(patience - 1))

        XCTAssertEqual(episode.observe(isOn: true, isScreenLocked: false, at: later(patience + 1)), .none)
    }
}
