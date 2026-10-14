import Carbon.HIToolbox
import Foundation

/// One keyboard input source as the menu lists it: its identifier, such as
/// `com.apple.keylayout.German`, is what config.json stores.
struct InputSource: Identifiable, Equatable {
    let id: String
    let name: String
}

/// The keyboard input sources enabled in System Settings, and switching
/// between them. Text Input Sources belongs on the main thread.
@MainActor
enum InputSources {
    static func enabled() -> [InputSource] {
        selectable().compactMap { source in
            guard let id = string(kTISPropertyInputSourceID, of: source) else { return nil }

            return InputSource(id: id, name: string(kTISPropertyLocalizedName, of: source) ?? id)
        }
    }

    static var currentID: String? {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else { return nil }

        return string(kTISPropertyInputSourceID, of: source)
    }

    /// False when no enabled source has that identifier, or macOS refused.
    @discardableResult
    static func select(_ id: String) -> Bool {
        guard let source = selectable().first(where: { string(kTISPropertyInputSourceID, of: $0) == id })
        else { return false }

        return TISSelectInputSource(source) == noErr
    }

    /// Keyboard sources only: palettes and dictation are input sources too.
    private static func selectable() -> [TISInputSource] {
        let filter = [
            kTISPropertyInputSourceCategory as String: kTISCategoryKeyboardInputSource as String,
            kTISPropertyInputSourceIsSelectCapable as String: true,
        ] as CFDictionary

        guard let list = TISCreateInputSourceList(filter, false)?.takeRetainedValue() as? [TISInputSource]
        else { return [] }

        return list
    }

    private static func string(_ property: CFString, of source: TISInputSource) -> String? {
        guard let pointer = TISGetInputSourceProperty(source, property) else { return nil }

        return Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
    }
}
