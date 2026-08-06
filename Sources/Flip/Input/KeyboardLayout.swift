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
    private static let lock = NSLock()
    private static var codesByCharacter: [Character: CGKeyCode] = [:]
    private static var isLoaded = false

    static func keyCode(for character: Character) -> CGKeyCode? {
        lock.lock()
        defer { lock.unlock() }

        if !isLoaded { reload() }

        return codesByCharacter[character]
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

    /// Caller holds the lock. There is no character-to-code direction in the API,
    /// so the whole keyboard is translated once and the result reversed.
    private static func reload() {
        isLoaded = true
        codesByCharacter = [:]

        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return }

        let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
        data.withUnsafeBytes { buffer in
            guard let layout = buffer.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self)
            else { return }

            for code in 0..<128 {
                guard let character = translate(CGKeyCode(code), with: layout) else { continue }
                // Lowest code wins: the main rows come before the numeric keypad,
                // so "1" resolves to the digit row rather than the keypad.
                if codesByCharacter[character] == nil {
                    codesByCharacter[character] = CGKeyCode(code)
                }
            }
        }
    }

    private static func translate(
        _ code: CGKeyCode,
        with layout: UnsafePointer<UCKeyboardLayout>
    ) -> Character? {
        var deadKeyState: UInt32 = 0
        var characters = [UniChar](repeating: 0, count: 4)
        var length = 0

        let status = UCKeyTranslate(
            layout,
            UInt16(code),
            UInt16(kUCKeyActionDisplay),
            0, // no modifiers: the unshifted character is what bindings are written as
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
