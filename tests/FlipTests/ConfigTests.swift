import CoreGraphics
import XCTest

@testable import Flip

final class AppBindingTests: XCTestCase {
    /// The common case, so it is what leaving the key out means.
    func testABindingWithoutUsesLeaderCarriesTheLeader() throws {
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
    /// ⌘ opens everything and ⌥ narrows to one application: the switcher people
    /// already reach for stays the big one.
    func testTheDefaultsFollowStockMacOS() throws {
        XCTAssertEqual(Settings().leader, .command)
        XCTAssertEqual(Settings().appSwitcher, .option)

        let swapped = Data(#"{"leader":["option"],"appSwitcher":["command"]}"#.utf8)
        let decoded = try JSONDecoder().decode(Settings.self, from: swapped)
        XCTAssertEqual(decoded.leader, .option)
        XCTAssertEqual(decoded.appSwitcher, .command)
    }

    func testTheTwoHotkeysMustDiffer() {
        var settings = Settings()
        XCTAssertTrue(settings.isValid)

        settings.appSwitcher = settings.leader
        XCTAssertFalse(settings.isValid)
    }

    func testAFileNamingOnlySomeKeysStillDecodes() throws {
        let json = Data(#"{"leader":["option"],"appSwitcher":["command"]}"#.utf8)

        let decoded = try JSONDecoder().decode(Settings.self, from: json)

        XCTAssertEqual(decoded.leader, .option)
        XCTAssertTrue(decoded.showThumbnails)
        XCTAssertEqual(decoded.overlayDelay, .short)
        XCTAssertTrue(decoded.excludedBundleIDs.isEmpty)
        XCTAssertFalse(decoded.showWindowsFromEverySpace)
    }

    /// ⇧⌥, not the halves' own modifier: the two share the arrows.
    func testTheDisplayMoveDefaultsToShiftOption() throws {
        XCTAssertEqual(Settings().displayMoveModifier, .shiftOption)

        let json = Data(#"{"leader":["option"]}"#.utf8)
        XCTAssertEqual(
            try JSONDecoder().decode(Settings.self, from: json).displayMoveModifier, .shiftOption
        )
    }

    func testTheShortcutLeaderIsItsOwnSetting() throws {
        var settings = Settings()
        settings.leader = .option
        settings.shortcutLeader = .controlCommand

        let round = try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(settings))

        XCTAssertEqual(round.leader, .option)
        XCTAssertEqual(round.shortcutLeader, .controlCommand)
    }

    func testTheWindowActionsDefaultToControlOption() throws {
        XCTAssertEqual(Settings().windowLeader, .optionControl)

        let json = Data(#"{"leader":["command"]}"#.utf8)

        XCTAssertEqual(
            try JSONDecoder().decode(Settings.self, from: json).windowLeader, .optionControl
        )
    }

    func testEveryWindowLeaderSurvivesARoundTrip() throws {
        for choice in ModifierChoice.allCases {
            var settings = Settings()
            settings.windowLeader = choice
            let round = try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(settings))

            XCTAssertEqual(round.windowLeader, choice)
        }
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

    /// One vocabulary for every modifier the file names, so a hand edit spells
    /// the switcher's leader the same way it spells the display move.
    func testEveryModifierIsWrittenAsKeywords() throws {
        var settings = Settings()
        settings.leader = .command
        settings.windowLeader = .optionControl
        settings.displayMoveModifier = .allThree

        let json = String(decoding: try JSONEncoder().encode(settings), as: UTF8.self)

        XCTAssertTrue(json.contains(#""leader":["command"]"#), json)
        XCTAssertTrue(json.contains(#""windowLeader":["option","control"]"#), json)
        XCTAssertTrue(json.contains(#""displayMoveModifier":["command","option","control"]"#), json)
    }

    func testKeywordsAreReadInAnyOrder() throws {
        let json = Data(#"{"windowLeader":["control","option"],"displayMoveModifier":["option","command","control"]}"#.utf8)

        let decoded = try JSONDecoder().decode(Settings.self, from: json)

        XCTAssertEqual(decoded.windowLeader, .optionControl)
        XCTAssertEqual(decoded.displayMoveModifier, .allThree)
    }

    /// A combination the setting does not offer is a broken file, not a silent
    /// reset to the default: the store keeps it for inspection.
    func testACombinationTheSettingDoesNotOfferIsRejected() {
        let json = Data(#"{"windowLeader":["shift","command"]}"#.utf8)

        XCTAssertThrowsError(try JSONDecoder().decode(Settings.self, from: json))
    }

    /// Keywords and nothing else, so there is one way to write a modifier.
    func testASingleWordIsNotAModifier() {
        let json = Data(#"{"windowLeader":"option-command"}"#.utf8)

        XCTAssertThrowsError(try JSONDecoder().decode(Settings.self, from: json))
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
final class ConfigStoreTests: XCTestCase {
    /// Temporary, because the store writes on every change and the real file is
    /// the user's live configuration.
    private func makeStore() -> ConfigStore {
        ConfigStore(file: directory().appendingPathComponent("config.json"))
    }

    private func directory() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("flip-tests-\(UUID().uuidString)")
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

        let reopened = ConfigStore(file: store.fileURL)
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

    /// The seed is one binding on purpose: every key it takes is one somebody
    /// has to find and clear before it is theirs, and the Finder is the only
    /// application that is certainly installed.
    func testTheSeedIsOneBindingForAnApplicationEveryMacHas() {
        XCTAssertEqual(DefaultBindings.all.count, 1)
        XCTAssertEqual(DefaultBindings.all.first?.key, "f")
        XCTAssertEqual(DefaultBindings.all.first?.bundleID, "com.apple.finder")
        XCTAssertEqual(DefaultBindings.all.first?.usesLeader, true)
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

    /// The router matches window actions before bindings, so ⌃⌥ as the leader
    /// makes u i j k and Return unreachable — silently, until this said so.
    func testALeaderThatCollidesWithAWindowActionIsReported() {
        let store = makeStore()
        store.add()
        store.setBundleID("com.example.app", for: store.bindings[0].id)
        store.setKey("u", for: store.bindings[0].id)

        XCTAssertEqual(
            store.issue(for: store.bindings[0], leader: ModifierChoice.optionControl.flags),
            .takenByWindowAction("Top left quarter")
        )
        XCTAssertNil(store.issue(for: store.bindings[0], leader: ModifierChoice.option.flags))
    }

    /// A bare binding never carries the leader, so it cannot collide with one.
    func testABareBindingIsNotAffectedByTheLeader() {
        let store = makeStore()
        store.add()
        store.setBundleID("com.example.app", for: store.bindings[0].id)
        store.setKey("u", for: store.bindings[0].id)
        store.setUsesLeader(false, for: store.bindings[0].id)

        XCTAssertNil(
            store.issue(for: store.bindings[0], leader: ModifierChoice.optionControl.flags)
        )
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

    func testEverySettingAndEveryBindingLiveInTheOneFile() throws {
        let store = makeStore()
        store.load()
        store.settings.leader = .controlCommand
        store.settings.showThumbnails = false
        store.add()
        store.setKey("5", for: store.bindings.last!.id)

        let reopened = ConfigStore(file: store.fileURL)
        reopened.load()

        XCTAssertEqual(reopened.settings.leader, .controlCommand)
        XCTAssertFalse(reopened.settings.showThumbnails)
        XCTAssertEqual(reopened.bindings.last?.key, "5")
    }

    /// Flat, so a hand edit reads as one key per setting rather than as two
    /// halves of a document.
    func testTheFileKeepsEverySettingAtTheTopLevel() throws {
        let store = makeStore()
        store.load()

        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: store.fileURL)) as? [String: Any]
        )

        XCTAssertNotNil(object["leader"])
        XCTAssertNotNil(object["shortcutLeader"])
        XCTAssertNotNil(object["bindings"] as? [[String: Any]])
    }

    /// Seeding is for a file that is not there. Emptying the list is an edit
    /// like any other, and must not come back with the Finder on F.
    func testAConfigWithoutBindingsIsNotReseeded() throws {
        let store = makeStore()
        store.load()
        for binding in store.bindings { store.remove(binding.id) }

        let reopened = ConfigStore(file: store.fileURL)
        reopened.load()

        XCTAssertTrue(reopened.bindings.isEmpty)
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
        let json = Data(#"{"leader":["option"]}"#.utf8)

        XCTAssertTrue(try JSONDecoder().decode(Settings.self, from: json).checkForUpdates)
    }
}
