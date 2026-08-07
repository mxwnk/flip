import CoreGraphics
import XCTest

@testable import Flip

final class AppBindingTests: XCTestCase {
    func testOlderFilesWithoutUsesLeaderDefaultToTheLeader() throws {
        let json = Data(#"[{"key":"s","bundleID":"com.spotify.client"}]"#.utf8)

        let decoded = try JSONDecoder().decode([AppBinding].self, from: json)

        XCTAssertEqual(decoded.count, 1)
        XCTAssertTrue(decoded[0].usesLeader)
    }

    func testTheIdentifierIsNotWrittenToTheFile() throws {
        let encoded = try JSONEncoder().encode([AppBinding(key: "s", bundleID: "a")])

        XCTAssertFalse(String(decoding: encoded, as: UTF8.self).contains("id"))
    }

    func testEncodingAndDecodingPreservesEveryField() throws {
        let original = AppBinding(key: "F1", bundleID: "com.mitchellh.ghostty", usesLeader: false)

        let decoded = try JSONDecoder()
            .decode([AppBinding].self, from: JSONEncoder().encode([original]))[0]

        XCTAssertEqual(decoded.key, original.key)
        XCTAssertEqual(decoded.bundleID, original.bundleID)
        XCTAssertEqual(decoded.usesLeader, original.usesLeader)
    }
}

final class SettingsTests: XCTestCase {
    func testTheTwoHotkeysMustDiffer() {
        var settings = Settings()
        XCTAssertTrue(settings.isValid)

        settings.appSwitcher = settings.leader
        XCTAssertFalse(settings.isValid)
    }

    func testAFileMissingNewerKeysStillDecodes() throws {
        let json = Data(#"{"leader":"option","appSwitcher":"command"}"#.utf8)

        let decoded = try JSONDecoder().decode(Settings.self, from: json)

        XCTAssertEqual(decoded.leader, .option)
        XCTAssertTrue(decoded.showThumbnails)
        XCTAssertEqual(decoded.overlayDelay, .short)
        XCTAssertTrue(decoded.excludedBundleIDs.isEmpty)
        XCTAssertFalse(decoded.showWindowsFromEverySpace)
    }

    /// The default has to stay off: turning it on for everyone who upgrades would
    /// silently widen the grid to windows they have never seen in it.
    /// The default has to stay the pair it always was: changing it under an
    /// upgrade would take away a shortcut somebody's fingers already know.
    func testTheDisplayMoveKeepsItsOldModifier() throws {
        XCTAssertEqual(Settings().displayMoveModifier, .shiftOption)

        let old = Data(#"{"leader":"option"}"#.utf8)
        XCTAssertEqual(
            try JSONDecoder().decode(Settings.self, from: old).displayMoveModifier, .shiftOption
        )
    }

    func testBothDisplayMoveChoicesSurviveARoundTrip() throws {
        for choice in DisplayMoveModifier.allCases {
            var settings = Settings()
            settings.displayMoveModifier = choice
            let round = try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(settings))

            XCTAssertEqual(round.displayMoveModifier, choice)
        }
    }

    func testWindowsFromEverySpaceIsOffUntilAsked() throws {
        XCTAssertFalse(Settings().showWindowsFromEverySpace)

        var settings = Settings()
        settings.showWindowsFromEverySpace = true
        let round = try JSONDecoder().decode(
            Settings.self, from: JSONEncoder().encode(settings)
        )

        XCTAssertTrue(round.showWindowsFromEverySpace)
    }

    func testEveryModifierChoiceHasDistinctFlags() {
        let flags = ModifierChoice.allCases.map(\.flags.rawValue)

        XCTAssertEqual(Set(flags).count, ModifierChoice.allCases.count)
    }

    func testOnlyTheImmediateChoiceHasNoDelay() {
        XCTAssertEqual(OverlayDelay.immediately.seconds, 0)
        for choice in OverlayDelay.allCases where choice != .immediately {
            XCTAssertGreaterThan(choice.seconds, 0, choice.rawValue)
        }
    }
}

final class ModifiersTests: XCTestCase {
    private func event(_ flags: CGEventFlags) -> CGEvent {
        let event = CGEvent(keyboardEventSource: nil, virtualKey: 48, keyDown: true)!
        event.flags = flags
        return event
    }

    func testOnlyTheInterestingModifiersSurvive() {
        let held = Modifiers.held(in: event([.maskAlternate, .maskNonCoalesced]))

        XCTAssertEqual(held, [.maskAlternate])
    }

    /// Caps lock must not be able to hold a finished overlay open.
    func testCapsLockIsIgnored() {
        XCTAssertFalse(Modifiers.anyHeld(in: event([.maskAlphaShift])))
    }

    func testNoModifiersMeansNoneHeld() {
        XCTAssertFalse(Modifiers.anyHeld(in: event([])))
    }

    func testCombinationsCompareExactly() {
        let held = Modifiers.held(in: event([.maskAlternate, .maskControl]))

        XCTAssertEqual(held, [.maskAlternate, .maskControl])
        XCTAssertNotEqual(held, [.maskAlternate])
    }
}

@MainActor
final class BindingStoreTests: XCTestCase {
    /// A temporary file, because the store writes on every change and the real one
    /// is the user's live configuration.
    private func makeStore() -> BindingStore {
        let file = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("flip-tests-\(UUID().uuidString)")
            .appendingPathComponent("bindings.json")

        return BindingStore(file: file)
    }

    func testAFreshStoreSeedsFromTheDefaults() {
        let store = makeStore()

        store.load()

        XCTAssertEqual(store.bindings.count, DefaultBindings.all.count)
    }

    func testWhatIsSavedIsWhatIsLoadedBack() {
        let store = makeStore()
        store.load()
        store.add()
        store.setKey("5", for: store.bindings.last!.id)
        store.setBundleID("com.example.app", for: store.bindings.last!.id)

        let reopened = BindingStore(file: store.fileURL)
        reopened.load()

        XCTAssertEqual(reopened.bindings.count, DefaultBindings.all.count + 1)
        XCTAssertEqual(reopened.bindings.last?.key, "5")
        XCTAssertEqual(reopened.bindings.last?.bundleID, "com.example.app")
    }

    func testKeysAreStoredLowercased() {
        let store = makeStore()
        store.add()
        store.setKey("S", for: store.bindings[0].id)

        XCTAssertEqual(store.bindings[0].key, "s")
    }

    /// Named keys are longer than one character and must keep their case.
    func testNamedKeysAreLeftAlone() {
        let store = makeStore()
        store.add()
        store.setKey("F1", for: store.bindings[0].id)

        XCTAssertEqual(store.bindings[0].key, "F1")
    }

    func testAnEmptyApplicationIsReported() {
        let store = makeStore()
        store.add()

        XCTAssertEqual(store.issue(for: store.bindings[0]), .noApplication)
    }

    func testTwoBindingsOnTheSameKeyClash() {
        let store = makeStore()
        store.add()
        store.add()
        for binding in store.bindings {
            store.setBundleID("com.example.app", for: binding.id)
            store.setKey("s", for: binding.id)
        }

        XCTAssertEqual(store.issue(for: store.bindings[0]), .duplicate)
    }

    /// The same key is fine on both sides of the modifier: Alt-F1 and a bare F1
    /// are different bindings.
    func testTheSameKeyWithAndWithoutTheLeaderDoesNotClash() {
        let store = makeStore()
        store.add()
        store.add()
        for binding in store.bindings {
            store.setBundleID("com.example.app", for: binding.id)
            store.setKey("F1", for: binding.id)
        }
        store.setUsesLeader(false, for: store.bindings[1].id)

        XCTAssertNil(store.issue(for: store.bindings[0]))
    }

    func testRemovingLeavesTheRest() {
        let store = makeStore()
        store.load()
        let before = store.bindings.count

        store.remove(store.bindings[0].id)

        XCTAssertEqual(store.bindings.count, before - 1)
    }
}

final class VersionComparisonTests: XCTestCase {
    /// The one that a string comparison gets wrong, and the reason this is not
    /// simply `latest > current`.
    func testTenIsNewerThanNine() {
        XCTAssertTrue(UpdateChecker.isNewer("0.10.0", than: "0.9.0"))
        XCTAssertFalse(UpdateChecker.isNewer("0.9.0", than: "0.10.0"))
    }

    func testTheLeadingVOfATagIsIgnored() {
        XCTAssertTrue(UpdateChecker.isNewer("v0.3.0", than: "0.2.0"))
        XCTAssertFalse(UpdateChecker.isNewer("v0.2.0", than: "0.2.0"))
    }

    func testTheSameVersionIsNotAnUpdate() {
        for version in ["0.2.0", "1.0", "3.4.5"] {
            XCTAssertFalse(UpdateChecker.isNewer(version, than: version), version)
        }
    }

    /// A development build running ahead of the last release must stay quiet.
    func testABuildAheadOfTheReleaseSeesNothing() {
        XCTAssertFalse(UpdateChecker.isNewer("0.2.0", than: "0.3.0"))
    }

    func testMissingComponentsCountAsZero() {
        XCTAssertTrue(UpdateChecker.isNewer("0.3", than: "0.2.9"))
        XCTAssertFalse(UpdateChecker.isNewer("0.2", than: "0.2.1"))
        XCTAssertFalse(UpdateChecker.isNewer("1.0.0", than: "1"))
    }

    /// Anything unparseable reads as zero, so a mangled tag can never look like
    /// an upgrade and pester everyone into clicking it.
    func testAMangledTagIsNotAnUpgrade() {
        for tag in ["", "latest", "v", "nightly-build"] {
            XCTAssertFalse(UpdateChecker.isNewer(tag, than: "0.2.0"), tag)
        }
    }

    func testAFileMissingTheUpdateKeyStillChecks() throws {
        let json = Data(#"{"leader":"option"}"#.utf8)

        XCTAssertTrue(try JSONDecoder().decode(Settings.self, from: json).checkForUpdates)
    }
}
