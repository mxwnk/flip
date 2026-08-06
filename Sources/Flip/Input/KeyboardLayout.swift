import Carbon.HIToolbox
import CoreGraphics
import Foundation

/// Maps characters to the physical keys that produce them.
///
/// Bindings are written as letters, but an event tap only ever sees virtual key
/// codes, and the two are not interchangeable: the key that types "z" on QWERTZ is
/// the one QWERTY calls "y". Hard-coding kVK_ANSI_* would quietly bind the wrong
/// key the first time a binding lands on one of the swapped positions.
enum KeyboardLayout {
    /// Keys that no character can express, so they can only be written by name.
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

    /// Resolves whatever a binding wrote: a single character against the current
    /// layout, or one of the named keys above.
    static func keyCode(forBinding key: String) -> CGKeyCode? {
        if key.count == 1, let character = key.first { return keyCode(for: character) }

        return namedKeys[key.uppercased()]
    }

    /// What Option plus this key types, but only when that is printable ASCII.
    ///
    /// "Produces a character" is not a useful warning: on a German layout every
    /// single alphanumeric key does — measured, 40 of 40 — but they produce ç, €,
    /// ƒ, ©, ∑ and other things nobody reaches for. The ASCII ones are the nine
    /// that matter, @ | [ ] { } ~ among them, and binding one of those takes it
    /// away everywhere, because the event tap swallows the keystroke.
    static func asciiOptionCharacter(for character: Character) -> Character? {
        withLayout { asciiOptionByCharacter[character] }
    }

    /// The whole mapping moves with the input source, so switching layouts has to
    /// throw it away. Rebuilding is deferred to the next lookup.
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

    /// Caller holds the lock. There is no character-to-code direction in the API,
    /// so the whole keyboard is translated once and the result reversed.
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
                // Lowest code wins: the main rows come before the numeric keypad,
                // so "1" resolves to the digit row rather than the keypad.
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

        // UCKeyTranslate wants the modifier flags shifted down out of their
        // NSEvent positions, which is what the >> 8 is for.
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
