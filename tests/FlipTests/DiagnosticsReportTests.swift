import XCTest

@testable import Flip

final class DiagnosticsReportTests: XCTestCase {
    private typealias Fact = DiagnosticsReport.Fact
    private typealias LogLine = DiagnosticsReport.LogLine

    private func report(log: [LogLine] = []) -> DiagnosticsReport {
        DiagnosticsReport(
            title: "Flip 9.9.9",
            sections: [
                [Fact(label: "macOS", value: "26")],
                [Fact(label: "Accessibility", value: "granted"), Fact(label: "Event tap", value: "running")],
            ],
            log: log
        )
    }

    func testEveryValueStartsInTheSameColumnAcrossSections() {
        let lines = report().factLines

        XCTAssertEqual(lines, [
            "Flip 9.9.9",
            "",
            "macOS:          26",
            "",
            "Accessibility:  granted",
            "Event tap:      running",
        ])
    }

    func testEveryMessageStartsInTheSameColumn() {
        let lines = report(log: [
            LogLine(time: "13:26:13.470", isError: false, category: "startup", message: "warming"),
            LogLine(time: "13:26:52.017", isError: false, category: "permissions", message: "granted"),
        ]).logLines

        XCTAssertEqual(lines, [
            "13:26:13.470     startup      warming",
            "13:26:52.017     permissions  granted",
        ])
    }

    func testAnErrorIsMarkedInAColumnOfItsOwn() {
        let lines = report(log: [
            LogLine(time: "13:26:13.470", isError: true, category: "eventtap", message: "tap was disabled"),
        ]).logLines

        XCTAssertEqual(lines, ["13:26:13.470  !  eventtap  tap was disabled"])
    }

    /// GitHub collapses runs of spaces outside a code block.
    func testTheCopiedLogIsFenced() {
        let text = report(log: [
            LogLine(time: "13:26:13.470", isError: false, category: "startup", message: "warming"),
        ]).plainText

        XCTAssertTrue(text.hasSuffix("Recent log:\n```\n13:26:13.470     startup  warming\n```"))
    }

    func testAnEmptyLogSaysSoUnfenced() {
        XCTAssertTrue(report().plainText.hasSuffix("Recent log:\n(none)"))
    }

    /// A wrapped line indents to these, so they must be where the text starts.
    func testTheColumnsAreWhereValuesAndMessagesStart() {
        let report = report(log: [
            LogLine(time: "13:26:13.470", isError: true, category: "eventtap", message: "tap was disabled"),
            LogLine(time: "13:26:14.000", isError: false, category: "permissions", message: "granted"),
        ])

        for line in report.factLines where line.hasPrefix("Accessibility") {
            XCTAssertEqual(line.dropFirst(report.factValueColumn), "granted")
        }
        XCTAssertEqual(report.logLines.map { $0.dropFirst(report.logMessageColumn) }, ["tap was disabled", "granted"])
    }

    func testAValueIsFoundByItsLabelInAnySection() {
        XCTAssertEqual(report().value(of: "Event tap"), "running")
        XCTAssertNil(report().value(of: "Missing"))
    }
}
