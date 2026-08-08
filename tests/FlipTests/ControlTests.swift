import XCTest

@testable import Flip
import FlipControl

/// The `flip` command and the application are separate binaries built from one
/// tree. Nothing at compile time makes them agree on the vocabulary, so it is
/// asserted here instead.
final class ControlTests: XCTestCase {
    func testEveryArrangementHasAName() {
        let names = WindowArrangement.allCases.map(\.controlName)

        XCTAssertEqual(Set(names).count, names.count, "two arrangements answer to the same name")
        XCTAssertEqual(Set(names), Set(ControlArrangement.names))
    }

    func testEveryNameTheCommandOffersResolves() {
        for name in ControlArrangement.names {
            XCTAssertNotNil(
                WindowArrangement(controlName: name),
                "`flip arrange \(name)` is offered but reaches nothing"
            )
        }
    }

    func testAnUnknownNameResolvesToNothing() {
        XCTAssertNil(WindowArrangement(controlName: "middle"))
        XCTAssertNil(WindowArrangement(controlName: ""))
    }

    /// A unix socket path is copied into a fixed-size buffer, so a home
    /// directory long enough to overflow it has to fail loudly rather than
    /// silently talking to a truncated path.
    func testTheSocketPathFitsAUnixSocket() {
        XCTAssertLessThanOrEqual(ControlSocket.path.utf8.count, ControlSocket.maximumPathLength)
    }

    func testTheCommandsSurviveTheWire() throws {
        let commands: [ControlCommand] = [
            .list, .focus(4711), .arrange("left-half"), .switcher, .pause, .resume,
        ]

        for command in commands {
            let encoded = try JSONEncoder().encode(command)
            let decoded = try JSONDecoder().decode(ControlCommand.self, from: encoded)

            XCTAssertEqual(
                try JSONEncoder().encode(decoded), encoded,
                "\(command) did not survive a round trip"
            )
        }
    }
}
