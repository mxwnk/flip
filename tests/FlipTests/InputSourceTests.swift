import XCTest

@testable import Flip

final class InputSourceRuleTests: XCTestCase {
    private let rules = [
        "com.microsoft.VSCode": "com.apple.keylayout.US",
        "com.tinyspeck.slackmacgap": "com.apple.keylayout.German",
    ]

    func testAnApplicationWithARuleGetsItsSource() {
        let wanted = InputSourceSwitcher.sourceToSelect(
            for: "com.microsoft.VSCode", rules: rules, current: "com.apple.keylayout.German"
        )

        XCTAssertEqual(wanted, "com.apple.keylayout.US")
    }

    func testASourceAlreadyOnIsNotSelectedAgain() {
        let wanted = InputSourceSwitcher.sourceToSelect(
            for: "com.microsoft.VSCode", rules: rules, current: "com.apple.keylayout.US"
        )

        XCTAssertNil(wanted)
    }

    func testAnApplicationWithoutARuleKeepsWhateverIsOn() {
        let wanted = InputSourceSwitcher.sourceToSelect(
            for: "com.apple.Safari", rules: rules, current: "com.apple.keylayout.German"
        )

        XCTAssertNil(wanted)
    }

    func testAnApplicationWithoutABundleIdIsLeftAlone() {
        XCTAssertNil(InputSourceSwitcher.sourceToSelect(for: nil, rules: rules, current: nil))
    }
}

final class InputSourceSettingsTests: XCTestCase {
    func testAFileWithoutInputSourcesStillLoads() throws {
        let settings = try JSONDecoder().decode(Settings.self, from: Data("{}".utf8))

        XCTAssertTrue(settings.inputSources.isEmpty)
    }

    func testInputSourcesSurviveARoundTrip() throws {
        var settings = Settings()
        settings.inputSources = ["com.microsoft.VSCode": "com.apple.keylayout.US"]

        let round = try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(settings))

        XCTAssertEqual(round.inputSources, ["com.microsoft.VSCode": "com.apple.keylayout.US"])
    }
}

@MainActor
final class InputSourceStoreTests: XCTestCase {
    private func makeStore() -> ConfigStore {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("flip-tests-\(UUID().uuidString)")

        return ConfigStore(file: directory.appendingPathComponent("config.json"))
    }

    func testAnAssignmentIsSavedAndReplacedPerApplication() {
        let store = makeStore()
        store.load()

        store.setInputSource("com.apple.keylayout.US", for: "com.microsoft.VSCode")
        store.setInputSource("com.apple.keylayout.ABC", for: "com.microsoft.VSCode")

        let reopened = ConfigStore(file: store.fileURL)
        reopened.load()
        XCTAssertEqual(reopened.settings.inputSources, ["com.microsoft.VSCode": "com.apple.keylayout.ABC"])
    }

    func testRemovingAnAssignmentForgetsIt() {
        let store = makeStore()
        store.load()
        store.setInputSource("com.apple.keylayout.US", for: "com.microsoft.VSCode")

        store.removeInputSource(for: "com.microsoft.VSCode")

        XCTAssertTrue(store.settings.inputSources.isEmpty)
    }
}

/// Against the input sources this Mac actually has enabled.
@MainActor
final class InputSourceSystemTests: XCTestCase {
    func testTheSourceThatIsOnIsAmongTheEnabledOnes() throws {
        let current = try XCTUnwrap(InputSources.currentID)

        XCTAssertTrue(InputSources.enabled().contains { $0.id == current })
    }

    func testAnUnknownSourceCannotBeSelected() {
        XCTAssertFalse(InputSources.select("dev.mxwnk.no-such-layout"))
    }
}
