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
            let name = "f\(number)"
            guard let code = KeyboardLayout.keyCode(forBinding: name) else {
                return XCTFail("\(name) resolves to no key")
            }

            XCTAssertEqual(KeyboardLayout.bindingKey(for: code), name)
        }
    }

    /// The keys the arrangements sit on. They type nothing, so without a name
    /// there is no way to write one down in config.json.
    func testTheArrowsAndReturnAreNamedKeys() {
        let named: [(String, Int, String)] = [
            ("left", kVK_LeftArrow, "←"), ("right", kVK_RightArrow, "→"),
            ("up", kVK_UpArrow, "↑"), ("down", kVK_DownArrow, "↓"),
            ("return", kVK_Return, "↩"),
        ]

        for (name, code, symbol) in named {
            XCTAssertEqual(KeyboardLayout.keyCode(forBinding: name), CGKeyCode(code), name)
            XCTAssertEqual(KeyboardLayout.bindingKey(for: CGKeyCode(code)), name)
            XCTAssertEqual(KeyboardLayout.symbol(forBinding: name), symbol, name)
        }
    }

    /// A file written by hand, where nobody is thinking about case.
    func testANamedKeyIsFoundWhateverItsCase() {
        XCTAssertEqual(KeyboardLayout.keyCode(forBinding: "F1"), KeyboardLayout.keyCode(forBinding: "f1"))
        XCTAssertEqual(KeyboardLayout.keyCode(forBinding: "Return"), CGKeyCode(kVK_Return))
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
