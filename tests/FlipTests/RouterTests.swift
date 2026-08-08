import Carbon.HIToolbox
import CoreGraphics
import XCTest

@testable import Flip

/// The router decides on the event tap's thread whether to swallow a key, and it
/// tracks the overlay's visibility itself to do it synchronously. Getting that
/// state wrong swallows arrows and escape system-wide, which is the worst thing
/// this project can do — so what is asserted here is mostly the return value of
/// `handle`, which is the swallow decision itself.
@MainActor
final class RouterTests: XCTestCase {
    private var presenter: FakePresenter!
    private var router: KeyRouter!

    override func setUp() {
        super.setUp()

        presenter = FakePresenter()
        router = KeyRouter(presenter: presenter, frontmost: FrontmostApp())
        router.apply([], settings: Settings())

        // The real wiring, so an overlay that closes on its own tells the router.
        presenter.onUnexpectedClose = { [weak router] in router?.overlayDidClose() }
    }

    // MARK: - Swallowing

    func testArrowsPassThroughWhileTheOverlayIsClosed() {
        XCTAssertNotNil(router.handle(type: .keyDown, event: key(kVK_RightArrow)))
        XCTAssertNotNil(router.handle(type: .keyDown, event: key(kVK_Escape)))
    }

    func testArrowsAreSwallowedWhileTheOverlayIsOpen() {
        openOverlay()

        XCTAssertNil(router.handle(type: .keyDown, event: key(kVK_RightArrow)))
        XCTAssertNil(router.handle(type: .keyDown, event: key(kVK_UpArrow)))
    }

    func testEscapeGivesTheKeysBack() {
        openOverlay()
        XCTAssertNil(router.handle(type: .keyDown, event: key(kVK_Escape)))

        XCTAssertNotNil(router.handle(type: .keyDown, event: key(kVK_RightArrow)))
    }

    func testReleasingTheModifierGivesTheKeysBack() {
        openOverlay()

        let released = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true)!
        released.type = .flagsChanged
        released.flags = []
        XCTAssertNotNil(router.handle(type: .flagsChanged, event: released))

        XCTAssertNotNil(router.handle(type: .keyDown, event: key(kVK_RightArrow)))
    }

    /// The router sets its flag before the presenter has had a chance to fail, so
    /// every path that gives up has to say so. One of them did not, and the keys
    /// stayed swallowed until the modifier came back up.
    func testAPresenterThatCannotOpenGivesTheKeysBack() {
        presenter.refusesToOpen = true

        XCTAssertNil(router.handle(type: .keyDown, event: key(kVK_Tab, flags: .maskCommand)))
        drainMainQueue()

        XCTAssertNotNil(
            router.handle(type: .keyDown, event: key(kVK_RightArrow)),
            "the overlay never opened, so the arrows are not the router's to take"
        )
    }

    func testARepeatIsSwallowedButNotActedOnTwice() {
        XCTAssertNil(router.handle(type: .keyDown, event: key(kVK_Tab, flags: .maskAlternate)))

        let repeated = key(kVK_Tab, flags: .maskAlternate)
        repeated.setIntegerValueField(.keyboardEventAutorepeat, value: 1)
        XCTAssertNil(router.handle(type: .keyDown, event: repeated))

        drainMainQueue()
        XCTAssertEqual(presenter.opened, 1, "a held Tab must not walk the grid by itself")
    }

    // MARK: - What wins

    /// The router matches window actions before it looks at any binding, so a
    /// leader that collides with one leaves the binding unreachable. This is the
    /// behaviour `BindingStore.issue` now warns about rather than a wish.
    func testAWindowActionBeatsABindingOnTheSameKeys() {
        var settings = Settings()
        settings.leader = .optionControl
        router.apply([AppBinding(key: "u", bundleID: "com.example.app")], settings: settings)

        XCTAssertNil(router.handle(
            type: .keyDown, event: key(kVK_ANSI_U, flags: [.maskAlternate, .maskControl])
        ))
        drainMainQueue()

        XCTAssertEqual(presenter.arranged, [.topLeftQuarter])
        XCTAssertTrue(presenter.reached.isEmpty, "the binding is shadowed, not merely second")
    }

    func testABindingIsReachedWhenTheLeaderDoesNotCollide() {
        router.apply([AppBinding(key: "u", bundleID: "com.example.app")], settings: Settings())

        XCTAssertNil(router.handle(type: .keyDown, event: key(kVK_ANSI_U, flags: .maskAlternate)))
        drainMainQueue()

        XCTAssertEqual(presenter.reached, ["com.example.app"])
        XCTAssertTrue(presenter.arranged.isEmpty)
    }

    func testAnUnboundKeyIsLeftAlone() {
        XCTAssertNotNil(router.handle(type: .keyDown, event: key(kVK_ANSI_A)))
        XCTAssertNotNil(router.handle(type: .keyDown, event: key(kVK_ANSI_A, flags: .maskAlternate)))
    }

    // MARK: - Helpers

    private func openOverlay() {
        XCTAssertNil(router.handle(type: .keyDown, event: key(kVK_Tab, flags: .maskAlternate)))
        drainMainQueue()
    }

    private func key(_ code: Int, flags: CGEventFlags = []) -> CGEvent {
        let event = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(code), keyDown: true)!
        event.flags = flags

        return event
    }

    /// The router hands work to main asynchronously, so the fake has not been
    /// told anything until the queue has run.
    private func drainMainQueue() {
        let arrived = expectation(description: "main queue drained")
        DispatchQueue.main.async { arrived.fulfill() }
        wait(for: [arrived], timeout: 1)
    }
}

@MainActor
private final class FakePresenter: SwitcherPresenting {
    var onUnexpectedClose: (() -> Void)?

    /// Stands in for every reason an open can come to nothing: no windows, or no
    /// frontmost bundle identifier.
    var refusesToOpen = false

    private(set) var opened = 0
    private(set) var reached: [String] = []
    private(set) var arranged: [WindowArrangement] = []

    func showAllWindows(step: Int) { open() }
    func showWindows(of bundleID: String, step: Int) { open() }
    func showFrontmostAppWindows(step: Int) { open() }

    private func open() {
        guard !refusesToOpen else {
            onUnexpectedClose?()
            return
        }

        opened += 1
    }

    func reachApplication(_ bundleID: String) { reached.append(bundleID) }
    func arrangeWindow(_ arrangement: WindowArrangement) { arranged.append(arrangement) }

    func move(by step: Int) {}
    func moveRow(by step: Int) {}
    func commit() {}
    func cancel() {}
}
