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
