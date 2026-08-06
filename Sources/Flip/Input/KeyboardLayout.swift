import Carbon.HIToolbox
import CoreGraphics
import Foundation

/// Maps characters to the physical keys that produce them. Hard-coded kVK_ANSI_*
/// would bind the wrong key: QWERTZ types "z" where QWERTY says "y".
enum KeyboardLayout {
    private static let namedKeys: [String: CGKeyCode] = [
        "F1": CGKeyCode(kVK_F1), "F2": CGKeyCode(kVK_F2), "F3": CGKeyCode(kVK_F3),
        "F4": CGKeyCode(kVK_F4), "F5": CGKeyCode(kVK_F5), "F6": CGKeyCode(kVK_F6),
        "F7": CGKeyCode(kVK_F7), "F8": CGKeyCode(kVK_F8), "F9": CGKeyCode(kVK_F9),
        "F10": CGKeyCode(kVK_F10), "F11": CGKeyCode(kVK_F11), "F12": CGKeyCode(kVK_F12),
    ]

    private static let lock = NSLock()
    private static var codesByCharacter: [Character: CGKeyCode] = [:]
    private static var asciiOptionByCharacter: [Character: Character] = [:]
    private static var isLoaded = false

    static func keyCode(for character: Character) -> CGKeyCode? {
        withLayout { codesByCharacter[character] }
    }

    static func keyCode(forBinding key: String) -> CGKeyCode? {
        if key.count == 1, let character = key.first { return keyCode(for: character) }

        return namedKeys[key.uppercased()]
    }

    /// Only printable ASCII, because "produces a character" is no warning at all:
    /// on a German layout 40 of 40 alphanumeric keys do, but they produce ç, €, ƒ.
    /// The nine ASCII ones — @ | [ ] { } ~ among them — are what a binding would
    /// take away everywhere.
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

    /// Caller holds the lock. The API has no character-to-code direction, so the
    /// whole keyboard is translated and reversed.
    private static func reload() {
        isLoaded = true
        codesByCharacter = [:]
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
