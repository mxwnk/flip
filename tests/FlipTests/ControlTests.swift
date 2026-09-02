import XCTest

@testable import Flip
import FlipControl

/// The `flip` command and the application are separate binaries built from one
/// tree. Nothing at compile time makes them agree on the vocabulary, so it is
/// asserted here instead.
final class ControlTests: XCTestCase {
    func testEveryArrangementHasAName() {
        let names = WindowArrangement.allCases.map(\.rawValue)

        XCTAssertEqual(Set(names).count, names.count, "two arrangements answer to the same name")
        XCTAssertEqual(Set(names), Set(ControlArrangement.names))
    }

    func testEveryNameTheCommandOffersResolves() {
        for name in ControlArrangement.names {
            XCTAssertNotNil(
                WindowArrangement(rawValue: name),
                "`flip arrange \(name)` is offered but reaches nothing"
            )
        }
    }

    func testAnUnknownNameResolvesToNothing() {
        XCTAssertNil(WindowArrangement(rawValue: "middle"))
        XCTAssertNil(WindowArrangement(rawValue: ""))
    }

    /// A unix socket path is copied into a fixed-size buffer, so a home
    /// directory long enough to overflow it has to fail loudly rather than
    /// silently talking to a truncated path.
    func testTheSocketPathFitsAUnixSocket() {
        XCTAssertLessThanOrEqual(ControlSocket.path.utf8.count, ControlSocket.maximumPathLength)
    }

    /// Keys sorted, because JSONEncoder does not promise an order and comparing
    /// two encodings of the same value is the point of the check.
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    func testTheCommandsSurviveTheWire() throws {
        let commands: [ControlCommand] = [
            .list, .focus(4711), .arrange("left-half"), .switcher, .pause, .resume,
            .permissions,
        ]

        for command in commands {
            let encoded = try encoder.encode(command)
            let decoded = try JSONDecoder().decode(ControlCommand.self, from: encoded)

            XCTAssertEqual(
                try encoder.encode(decoded), encoded,
                "\(command) did not survive a round trip"
            )
        }
    }

    /// The answers travel the same wire and are just as easy to break by adding
    /// a case on one side only.
    func testTheAnswersSurviveTheWire() throws {
        let responses: [ControlResponse] = [
            .windows([ControlWindow(id: 7, app: "Finder", title: "Downloads", minimized: false)]),
            .permissions(ControlPermissions(accessibility: true, screenRecording: false)),
            .ok,
            .failure("no window with id 7"),
        ]

        for response in responses {
            let encoded = try encoder.encode(response)
            let decoded = try JSONDecoder().decode(ControlResponse.self, from: encoded)

            XCTAssertEqual(
                try encoder.encode(decoded), encoded,
                "\(response) did not survive a round trip"
            )
        }
    }

    func testAGrantIsOnlyCompleteWithBoth() {
        XCTAssertTrue(ControlPermissions(accessibility: true, screenRecording: true).isComplete)
        XCTAssertFalse(ControlPermissions(accessibility: true, screenRecording: false).isComplete)
        XCTAssertFalse(ControlPermissions(accessibility: false, screenRecording: true).isComplete)
    }
}
