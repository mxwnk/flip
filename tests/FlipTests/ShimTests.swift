import XCTest

@testable import Flip
import CAXShim

/// `_AXUIElementGetWindow` is `weak_import`, so an absent symbol leaves the
/// pointer NULL instead of killing the process at launch.
@MainActor
final class ShimTests: XCTestCase {
    func testTheSymbolIsPresentOnThisSystem() {
        XCTAssertTrue(
            FlipCanReadWindowIDs(),
            "unsupported here; the point is that it says so instead of dying"
        )
    }

    func testTheWrapperAnswersForARealWindow() {
        var id: CGWindowID = 0
        let system = AXUIElementCreateSystemWide()

        // The system-wide element owns no window: must fail, not trap.
        XCTAssertNotEqual(FlipReadWindowID(system, &id), .success)
    }

    func testTheReportNamesAnUnsupportedSystem() {
        let unsupported = Diagnostics.report(
            status: .init(accessibility: true, screenRecording: true),
            isPaused: false,
            settings: Settings(),
            bindingCount: 1,
            canReadWindowIDs: false,
            secureInputHolder: nil,
            windowCount: 0
        )
        XCTAssertTrue(unsupported.contains("Window ids: UNSUPPORTED ON THIS SYSTEM"))

        let fine = Diagnostics.report(
            status: .init(accessibility: true, screenRecording: true),
            isPaused: false,
            settings: Settings(),
            bindingCount: 1,
            canReadWindowIDs: true,
            secureInputHolder: nil,
            windowCount: 3
        )
        XCTAssertTrue(fine.contains("Window ids: available"))
        XCTAssertTrue(fine.contains("Secure input: off"))
    }

    func testDiagnosticsNameWhoeverHoldsSecureInput() {
        let report = Diagnostics.report(
            status: .init(accessibility: true, screenRecording: true),
            isPaused: false,
            settings: Settings(),
            bindingCount: 1,
            canReadWindowIDs: true,
            secureInputHolder: SecureInputHolder(pid: 42, name: "Vault"),
            windowCount: 3
        )

        XCTAssertTrue(report.contains("Secure input: ON, held by Vault (pid 42)"))
    }

    func testAnUnnamedSecureInputHolderIsStillDescribed() {
        XCTAssertEqual(SecureInputHolder(pid: 7, name: nil).description, "pid 7")
        XCTAssertEqual(SecureInputHolder(pid: nil, name: nil).description, "an unknown process")
    }
}
