import Carbon.HIToolbox
import CoreGraphics
import Foundation

/// Characters to the physical keys that produce them. Hard-coded kVK_ANSI_*
/// would bind the wrong key: QWERTZ types "z" where QWERTY says "y".
enum KeyboardLayout {
    /// The keys that produce no character of their own. The name is what a
    /// binding and an arrangement are written as in config.json; the symbol is
    /// what the settings window draws on the keycap.
    private static let namedKeys: [(name: String, code: CGKeyCode, symbol: String)] = [
        ("f1", CGKeyCode(kVK_F1), "F1"), ("f2", CGKeyCode(kVK_F2), "F2"),
        ("f3", CGKeyCode(kVK_F3), "F3"), ("f4", CGKeyCode(kVK_F4), "F4"),
        ("f5", CGKeyCode(kVK_F5), "F5"), ("f6", CGKeyCode(kVK_F6), "F6"),
        ("f7", CGKeyCode(kVK_F7), "F7"), ("f8", CGKeyCode(kVK_F8), "F8"),
        ("f9", CGKeyCode(kVK_F9), "F9"), ("f10", CGKeyCode(kVK_F10), "F10"),
        ("f11", CGKeyCode(kVK_F11), "F11"), ("f12", CGKeyCode(kVK_F12), "F12"),
        ("left", CGKeyCode(kVK_LeftArrow), "←"), ("right", CGKeyCode(kVK_RightArrow), "→"),
        ("up", CGKeyCode(kVK_UpArrow), "↑"), ("down", CGKeyCode(kVK_DownArrow), "↓"),
        ("return", CGKeyCode(kVK_Return), "↩"),
    ]

    private static let lock = NSLock()
    private static var codesByCharacter: [Character: CGKeyCode] = [:]
    private static var charactersByCode: [CGKeyCode: Character] = [:]
    private static var asciiOptionByCharacter: [Character: Character] = [:]
    private static var isLoaded = false

    static func keyCode(for character: Character) -> CGKeyCode? {
        withLayout { codesByCharacter[character] }
    }

    /// The other direction, for drawing the keyboard: a picture labelled from a
    /// hard-coded American layout puts Z and Y wrong on a German one.
    static func character(for code: CGKeyCode) -> Character? {
        withLayout { charactersByCode[code] }
    }

    static func keyCode(forBinding key: String) -> CGKeyCode? {
        if key.count == 1, let character = key.first { return keyCode(for: character) }

        return named(key)?.code
    }

    /// What to draw on a keycap: an arrow rather than the word for it, and the
    /// character itself for everything a keyboard types.
    static func symbol(forBinding key: String) -> String {
        named(key)?.symbol ?? key.uppercased()
    }

    private static func named(_ key: String) -> (name: String, code: CGKeyCode, symbol: String)? {
        namedKeys.first { $0.name.caseInsensitiveCompare(key) == .orderedSame }
    }

    /// The inverse, for writing down a key that was pressed. Named keys win: F1
    /// is stored as "f1" rather than as whatever the layout says that key types,
    /// which on some of them is a character nobody can produce on purpose.
    static func bindingKey(for code: CGKeyCode) -> String? {
        if let named = namedKeys.first(where: { $0.code == code })?.name { return named }
        guard let character = character(for: code) else { return nil }

        return String(character)
    }

    /// Only printable ASCII: "produces a character" warns about nothing, since
    /// on a German layout all 40 alphanumeric keys do — but they produce ç, €, ƒ.
    /// The nine ASCII ones are what a binding actually takes away.
    static func asciiOptionCharacter(for character: Character) -> Character? {
        withLayout { asciiOptionByCharacter[character] }
    }

    /// The mapping moves with the input source; rebuilt on the next lookup.
    static func invalidate() {
        lock.lock()
        isLoaded = false
        lock.unlock()
    }

    static func observeInputSourceChanges(onChange: @escaping () -> Void) {
        DistributedNotificationCenter.default.addObserver(
            forName: .init(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil,
            queue: .main
        ) { _ in
            invalidate()
            onChange()
        }
    }

    private static func withLayout<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }

        if !isLoaded { reload() }

        return body()
    }

    /// Caller holds the lock. The API has no character-to-code direction, so
    /// the whole keyboard is translated and reversed.
    private static func reload() {
        isLoaded = true
        codesByCharacter = [:]
        charactersByCode = [:]
        asciiOptionByCharacter = [:]

        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return }

        let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
        data.withUnsafeBytes { buffer in
            guard let layout = buffer.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self)
            else { return }

            for code in 0..<128 {
                guard let character = translate(CGKeyCode(code), layout: layout) else { continue }

                charactersByCode[CGKeyCode(code)] = character

                // Lowest code wins, so "1" is the digit row and not the keypad.
                guard codesByCharacter[character] == nil else { continue }

                codesByCharacter[character] = CGKeyCode(code)

                if let shifted = translate(CGKeyCode(code), layout: layout, holdingOption: true),
                   shifted != character,
                   shifted.isASCII, shifted.isLetter || shifted.isNumber || shifted.isPunctuation
                       || shifted.isSymbol
                {
                    asciiOptionByCharacter[character] = shifted
                }
            }
        }
    }

    private static func translate(
        _ code: CGKeyCode,
        layout: UnsafePointer<UCKeyboardLayout>,
        holdingOption: Bool = false
    ) -> Character? {
        var deadKeyState: UInt32 = 0
        var characters = [UniChar](repeating: 0, count: 4)
        var length = 0

        // UCKeyTranslate wants the flags shifted out of their NSEvent positions.
        let modifiers = holdingOption ? UInt32((optionKey >> 8) & 0xFF) : 0

        let status = UCKeyTranslate(
            layout,
            UInt16(code),
            UInt16(kUCKeyActionDisplay),
            modifiers,
            UInt32(LMGetKbdType()),
            OptionBits(kUCKeyTranslateNoDeadKeysBit),
            &deadKeyState,
            characters.count,
            &length,
            &characters
        )

        guard status == noErr, length == 1 else { return nil }

        return String(utf16CodeUnits: characters, count: length).first
    }
}
