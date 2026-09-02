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
        XCTAssertEqual(Settings().switcher.leader, .command)
        XCTAssertEqual(Settings().switcher.applicationLeader, .option)

        let swapped = Data(#"{"switcher":{"leader":["option"],"applicationLeader":["command"]}}"#.utf8)
        let decoded = try JSONDecoder().decode(Settings.self, from: swapped)
        XCTAssertEqual(decoded.switcher.leader, .option)
        XCTAssertEqual(decoded.switcher.applicationLeader, .command)
    }

    func testTheTwoHotkeysMustDiffer() {
        var settings = Settings()
        XCTAssertTrue(settings.switcher.isValid)

        settings.switcher.applicationLeader = settings.switcher.leader
        XCTAssertFalse(settings.switcher.isValid)
    }

    /// A group is a page of the settings window, so a file that names one page
    /// leaves the other four at their defaults rather than failing.
    func testAFileNamingOnlySomeGroupsStillDecodes() throws {
        let json = Data(#"{"switcher":{"leader":["option"]}}"#.utf8)

        let decoded = try JSONDecoder().decode(Settings.self, from: json)

        XCTAssertEqual(decoded.switcher.leader, .option)
        XCTAssertTrue(decoded.switcher.showThumbnails)
        XCTAssertEqual(decoded.switcher.overlayDelay, .short)
        XCTAssertEqual(decoded.shortcuts.leader, .option)
        XCTAssertEqual(decoded.arrange.leader, .optionControl)
        XCTAssertTrue(decoded.general.checkForUpdates)
        XCTAssertTrue(decoded.excluded.isEmpty)
    }

    /// ⇧⌥, not the halves' own modifier: the two share the arrows.
    func testTheDisplayMoveDefaultsToShiftOption() throws {
        XCTAssertEqual(Settings().arrange.displayMove, .shiftOption)

        let json = Data(#"{"arrange":{"leader":["option","command"]}}"#.utf8)
        XCTAssertEqual(
            try JSONDecoder().decode(Settings.self, from: json).arrange.displayMove, .shiftOption
        )
    }

    /// Three groups name a leader, and each one is its own: the switcher's is
    /// held while you read a grid, the shortcuts' is tapped and let go.
    func testEachGroupHasItsOwnLeader() throws {
        var settings = Settings()
        settings.switcher.leader = .option
        settings.shortcuts.leader = .controlCommand
        settings.arrange.leader = .optionCommand

        let round = try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(settings))

        XCTAssertEqual(round.switcher.leader, .option)
        XCTAssertEqual(round.shortcuts.leader, .controlCommand)
        XCTAssertEqual(round.arrange.leader, .optionCommand)
    }

    func testEveryWindowLeaderSurvivesARoundTrip() throws {
        for choice in ModifierChoice.allCases {
            var settings = Settings()
            settings.arrange.leader = choice
            let round = try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(settings))

            XCTAssertEqual(round.arrange.leader, choice)
        }
    }

    func testBothDisplayMoveChoicesSurviveARoundTrip() throws {
        for choice in DisplayMoveModifier.allCases {
            var settings = Settings()
            settings.arrange.displayMove = choice
            let round = try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(settings))

            XCTAssertEqual(round.arrange.displayMove, choice)
        }
    }

    func testWindowsFromEverySpaceIsOffUntilAsked() throws {
        XCTAssertFalse(Settings().switcher.showWindowsFromEverySpace)

        var settings = Settings()
        settings.switcher.showWindowsFromEverySpace = true
        let round = try JSONDecoder().decode(
            Settings.self, from: JSONEncoder().encode(settings)
        )

        XCTAssertTrue(round.switcher.showWindowsFromEverySpace)
    }

    /// The file is the settings window on disk: a page per group, and the
    /// exclusions and bindings where the page that edits them is.
    func testTheGroupsAreTheSettingsPages() throws {
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: try JSONEncoder().encode(Settings()))
                as? [String: Any]
        )

        XCTAssertEqual(Set(object.keys), ["general", "switcher", "shortcuts", "arrange", "excluded"])
        XCTAssertNotNil((object["shortcuts"] as? [String: Any])?["bindings"])
        XCTAssertNotNil(object["excluded"] as? [String])
    }

    /// Every arrangement is in the file, by the name `flip arrange` gives it —
    /// the keys used to live only in the source.
    func testEveryArrangementKeyIsInTheFile() throws {
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: try JSONEncoder().encode(Settings()))
                as? [String: Any]
        )
        let keys = try XCTUnwrap(
            (object["arrange"] as? [String: Any])?["keys"] as? [String: String]
        )

        XCTAssertEqual(Set(keys.keys), Set(WindowArrangement.allCases.map(\.rawValue)))
        XCTAssertEqual(keys["left-half"], "left")
        XCTAssertEqual(keys["maximize"], "return")
    }

    func testNamingOneArrangementKeyLeavesTheRest() throws {
        let json = Data(#"{"arrange":{"keys":{"maximize":"m"}}}"#.utf8)

        let decoded = try JSONDecoder().decode(Settings.self, from: json)

        XCTAssertEqual(decoded.arrange.keys[.maximize], "m")
        XCTAssertEqual(decoded.arrange.keys[.leftHalf], "left")
        XCTAssertEqual(decoded.arrange.keys.count, WindowArrangement.allCases.count)
    }

    /// A name no arrangement answers to, like a modifier combination nothing
    /// offers: the file is wrong and says so.
    func testAnUnknownArrangementNameIsRejected() {
        let json = Data(#"{"arrange":{"keys":{"middle":"m"}}}"#.utf8)

        XCTAssertThrowsError(try JSONDecoder().decode(Settings.self, from: json))
    }

    /// One vocabulary for every modifier the file names, so a hand edit spells
    /// the switcher's leader the same way it spells the display move.
    func testEveryModifierIsWrittenAsKeywords() throws {
        var settings = Settings()
        settings.switcher.leader = .command
        settings.arrange.leader = .optionControl
        settings.arrange.displayMove = .allThree

        let json = String(decoding: try JSONEncoder().encode(settings), as: UTF8.self)

        XCTAssertTrue(json.contains(#""leader":["command"]"#), json)
        XCTAssertTrue(json.contains(#""leader":["option","control"]"#), json)
        XCTAssertTrue(json.contains(#""displayMove":["command","option","control"]"#), json)
    }

    func testKeywordsAreReadInAnyOrder() throws {
        let json = Data(#"{"arrange":{"leader":["control","option"],"displayMove":["option","command","control"]}}"#.utf8)

        let decoded = try JSONDecoder().decode(Settings.self, from: json)

        XCTAssertEqual(decoded.arrange.leader, .optionControl)
        XCTAssertEqual(decoded.arrange.displayMove, .allThree)
    }

    /// A combination the setting does not offer is a broken file, not a silent
    /// reset to the default: the store keeps it for inspection.
    func testACombinationTheSettingDoesNotOfferIsRejected() {
        let json = Data(#"{"arrange":{"leader":["shift","command"]}}"#.utf8)

        XCTAssertThrowsError(try JSONDecoder().decode(Settings.self, from: json))
    }

    /// Keywords and nothing else, so there is one way to write a modifier.
    func testASingleWordIsNotAModifier() {
        let json = Data(#"{"arrange":{"leader":"option-command"}}"#.utf8)

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

    /// The seed is a binding like any other, so a test about one binding starts
    /// by saying that it is the only one.
    private func makeEmptyStore() -> ConfigStore {
        let store = makeStore()
        store.settings.shortcuts.bindings = []

        return store
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
        let store = makeEmptyStore()
        store.add()
        store.setKey("S", for: store.bindings[0].id)

        XCTAssertEqual(store.bindings[0].key, "s")
    }

    /// Named keys are longer than one character and must keep their case.
    func testNamedKeysAreLeftAlone() {
        let store = makeEmptyStore()
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
        let store = makeEmptyStore()
        store.add()

        XCTAssertEqual(store.issue(for: store.bindings[0]), .noApplication)
    }

    func testTwoBindingsOnTheSameKeyClash() {
        let store = makeEmptyStore()
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
        let store = makeEmptyStore()
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
        let store = makeEmptyStore()
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
        let store = makeEmptyStore()
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
        store.settings.switcher.leader = .controlCommand
        store.settings.switcher.showThumbnails = false
        store.add()
        store.setKey("5", for: store.bindings.last!.id)

        let reopened = ConfigStore(file: store.fileURL)
        reopened.load()

        XCTAssertEqual(reopened.settings.switcher.leader, .controlCommand)
        XCTAssertFalse(reopened.settings.switcher.showThumbnails)
        XCTAssertEqual(reopened.bindings.last?.key, "5")
    }

    /// A group per page of the settings window, so a hand edit is found where
    /// the switch that changes it is.
    func testTheFileIsGroupedLikeTheSettingsWindow() throws {
        let store = makeStore()
        store.load()

        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: store.fileURL)) as? [String: Any]
        )

        XCTAssertEqual(Set(object.keys), ["general", "switcher", "shortcuts", "arrange", "excluded"])
        XCTAssertNotNil((object["switcher"] as? [String: Any])?["leader"])
        XCTAssertNotNil((object["shortcuts"] as? [String: Any])?["bindings"] as? [[String: Any]])
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
        let json = Data(#"{"switcher":{"leader":["option"]}}"#.utf8)

        XCTAssertTrue(
            try JSONDecoder().decode(Settings.self, from: json).general.checkForUpdates
        )
    }
}



