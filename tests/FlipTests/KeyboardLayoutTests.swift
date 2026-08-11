import Carbon.HIToolbox
import CoreGraphics
import XCTest

@testable import Flip

/// Recording a key writes down what was pressed, and the router later resolves
/// that back to a key code. The two directions have to agree, or the editor
/// cheerfully saves a binding that can never fire.
final class BindingKeyTests: XCTestCase {
    private let everyKeyOnTheBoard = CGKeyCode(0)...CGKeyCode(127)

    /// The reason the recorder exists: a text field could not type these, and
    /// the key they nominally produce is no use as a binding.
    func testTheFunctionKeysAreRecordedByName() {
        for number in 1...12 {
            let name = "F\(number)"
            guard let code = KeyboardLayout.keyCode(forBinding: name) else {
                return XCTFail("\(name) resolves to no key")
            }

            XCTAssertEqual(KeyboardLayout.bindingKey(for: code), name)
        }
    }

    /// What the editor guarantees: whatever a keypress is written down as, the
    /// router finds a key for it again. Anything else shows up as "no key
    /// produces this on the current layout" against a key that plainly does.
    func testEveryRecordedKeyResolvesToAKeyAgain() {
        for code in everyKeyOnTheBoard {
            guard let key = KeyboardLayout.bindingKey(for: code) else { continue }

            XCTAssertNotNil(
                KeyboardLayout.keyCode(forBinding: key),
                "key code \(code) was recorded as '\(key)', which resolves to nothing"
            )
        }
    }

    /// Modifiers, and the keys the layout has nothing to say about, are not
    /// bindings — the recorder has to keep waiting rather than store a blank.
    func testAKeyThatTypesNothingIsNotRecorded() {
        XCTAssertNil(KeyboardLayout.bindingKey(for: CGKeyCode(kVK_Shift)))
        XCTAssertNil(KeyboardLayout.bindingKey(for: CGKeyCode(kVK_Command)))
    }
}
