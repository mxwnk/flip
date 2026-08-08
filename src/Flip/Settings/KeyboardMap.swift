import Carbon.HIToolbox
import CoreGraphics
import SwiftUI

/// A picture of the keyboard with the keys Flip uses lit up. ⌃⌥⌘⇧ mean nothing
/// until you see which physical key each one is, so the modifiers carry the word
/// as well as the symbol. Letters follow the layout in use: a German keyboard
/// shows Z where an American one shows Y.
struct KeyboardMap: View {
    let keys: Set<CGKeyCode>
    let modifiers: CGEventFlags
    @Binding var order: ModifierRowOrder

    private let unit: CGFloat = 26
    private let gap: CGFloat = 3

    var body: some View {
        VStack(spacing: 6) {
            VStack(spacing: gap) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: gap) {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, key in
                            cap(key)
                        }
                    }
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.04))
            )

            HStack(alignment: .firstTextBaseline) {
                if !legend.isEmpty {
                    Text(legend)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 16)

                // With the picture rather than in a tab: it changes nothing
                // about Flip, only whether the drawing matches the desk.
                Picker("", selection: $order) {
                    ForEach(ModifierRowOrder.allCases) { choice in
                        Text(choice.label).tag(choice)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .font(.caption)
                .fixedSize()
            }
        }
    }

    // Named steps rather than one chain: the type checker gives up otherwise.
    private func cap(_ key: Key) -> some View {
        let lit = isLit(key)
        let size: CGFloat = key.caption == nil ? 11 : 9
        let weight: Font.Weight = lit ? .semibold : .regular
        let ink: Color = lit ? .white : .secondary
        let fill: Color = lit ? Theme.selectedStroke : Color.primary.opacity(0.07)
        let width = unit * key.width + gap * (key.width - 1)

        return Text(label(for: key))
            .font(.system(size: size, weight: weight))
            .foregroundStyle(ink)
            .lineLimit(2)
            // The captions are the point of this view, so they shrink rather
            // than truncate — "comm…" helps nobody.
            .minimumScaleFactor(0.7)
            .multilineTextAlignment(.center)
            .frame(width: width, height: unit)
            .background(RoundedRectangle(cornerRadius: 4).fill(fill))
    }

    /// The letter this key types, or a fixed name for the ones that type
    /// nothing — escape, the arrows, the modifiers.
    private func label(for key: Key) -> String {
        if let caption = key.caption {
            return key.name.map { "\($0)\n\(caption)" } ?? caption
        }
        if let name = key.name { return name }
        guard let code = key.code, let character = KeyboardLayout.character(for: code)
        else { return "" }

        // Upper case only where it stays one key's worth: ß becomes SS otherwise.
        let text = String(character)
        let upper = text.uppercased()

        return upper.count == 1 ? upper : text
    }

    private func isLit(_ key: Key) -> Bool {
        if let flag = key.modifier { return modifiers.contains(flag) }
        guard let code = key.code else { return false }

        return keys.contains(code)
    }

    private var legend: String {
        var parts: [String] = []
        if modifiers.contains(.maskControl) { parts.append("⌃ control") }
        if modifiers.contains(.maskAlternate) { parts.append("⌥ option") }
        if modifiers.contains(.maskShift) { parts.append("⇧ shift") }
        if modifiers.contains(.maskCommand) { parts.append("⌘ command") }

        return parts.isEmpty ? "" : parts.joined(separator: " · ")
    }

    // MARK: - The keyboard itself

    private struct Key {
        var code: CGKeyCode?
        /// Fixed name for keys that type nothing, or the symbol above a caption.
        var name: String?
        /// The word under the symbol, for the modifiers nobody can read.
        var caption: String?
        var modifier: CGEventFlags?
        var width: CGFloat = 1
    }

    private static func letter(_ code: Int) -> Key { Key(code: CGKeyCode(code)) }
    private static func named(_ name: String, _ code: Int? = nil, width: CGFloat = 1) -> Key {
        Key(code: code.map(CGKeyCode.init), name: name, width: width)
    }
    private static func modifier(
        _ symbol: String, _ caption: String, _ flag: CGEventFlags, width: CGFloat = 1
    ) -> Key {
        Key(name: symbol, caption: caption, modifier: flag, width: width)
    }

    /// Letters follow the layout, shape follows the hardware, and the two are
    /// independent: a German layout is typed on plenty of ANSI keyboards, which
    /// have no key between left shift and Z. The bottom row follows the setting,
    /// because macOS knows the shape but cannot know where command sits.
    private var rows: [[Key]] {
        let shape = Int(KBGetLayoutType(Int16(LMGetKbdType()))) == kKeyboardANSI
            ? Self.ansi
            : Self.iso

        return shape + [bottom(order)]
    }

    private static let common: [Key] = [
        named("esc", kVK_Escape, width: 1.5),
        named("F1", kVK_F1), named("F2", kVK_F2), named("F3", kVK_F3),
        named("F4", kVK_F4), named("F5", kVK_F5), named("F6", kVK_F6),
        named("F7", kVK_F7), named("F8", kVK_F8), named("F9", kVK_F9),
        named("F10", kVK_F10), named("F11", kVK_F11), named("F12", kVK_F12),
    ]

    private func bottom(_ order: ModifierRowOrder) -> [Key] {
        let control = Self.modifier("⌃", "control", .maskControl, width: 1.4)
        let option = Self.modifier("⌥", "option", .maskAlternate, width: 1.4)
        let command = Self.modifier("⌘", "command", .maskCommand, width: 1.8)
        let left = order == .appleStyle ? [control, option, command] : [control, command, option]
        // Two on the right, not three: the asymmetry every keyboard has, and
        // mirroring all three made the row stick out past those above.
        let right = left.suffix(2).reversed()

        return left + [
        Self.named("space", nil, width: 3.0),
    ] + right + [
        // Four in a row rather than an inverted T: each has to light up alone.
        Self.named("←", kVK_LeftArrow),
        Self.named("↓", kVK_DownArrow),
        Self.named("↑", kVK_UpArrow),
        Self.named("→", kVK_RightArrow),
        ]
    }

    private static let ansi: [[Key]] = [
        common,
        [
            letter(kVK_ANSI_Grave),
            letter(kVK_ANSI_1), letter(kVK_ANSI_2), letter(kVK_ANSI_3), letter(kVK_ANSI_4),
            letter(kVK_ANSI_5), letter(kVK_ANSI_6), letter(kVK_ANSI_7), letter(kVK_ANSI_8),
            letter(kVK_ANSI_9), letter(kVK_ANSI_0),
            letter(kVK_ANSI_Minus), letter(kVK_ANSI_Equal),
            named("⌫", kVK_Delete, width: 1.5),
        ],
        [
            named("⇥", kVK_Tab, width: 1.5),
            letter(kVK_ANSI_Q), letter(kVK_ANSI_W), letter(kVK_ANSI_E), letter(kVK_ANSI_R),
            letter(kVK_ANSI_T), letter(kVK_ANSI_Y), letter(kVK_ANSI_U), letter(kVK_ANSI_I),
            letter(kVK_ANSI_O), letter(kVK_ANSI_P),
            letter(kVK_ANSI_LeftBracket), letter(kVK_ANSI_RightBracket),
            letter(kVK_ANSI_Backslash),
        ],
        [
            named("⇪", nil, width: 1.8),
            letter(kVK_ANSI_A), letter(kVK_ANSI_S), letter(kVK_ANSI_D), letter(kVK_ANSI_F),
            letter(kVK_ANSI_G), letter(kVK_ANSI_H), letter(kVK_ANSI_J), letter(kVK_ANSI_K),
            letter(kVK_ANSI_L),
            letter(kVK_ANSI_Semicolon), letter(kVK_ANSI_Quote),
            named("↩", kVK_Return, width: 1.7),
        ],
        [
            modifier("⇧", "shift", .maskShift, width: 2.25),
            letter(kVK_ANSI_Z), letter(kVK_ANSI_X), letter(kVK_ANSI_C), letter(kVK_ANSI_V),
            letter(kVK_ANSI_B), letter(kVK_ANSI_N), letter(kVK_ANSI_M),
            letter(kVK_ANSI_Comma), letter(kVK_ANSI_Period), letter(kVK_ANSI_Slash),
            modifier("⇧", "shift", .maskShift, width: 2.25),
        ],
    ]

    private static let iso: [[Key]] = [
        common,
        [
            letter(kVK_ANSI_Grave),
            letter(kVK_ANSI_1), letter(kVK_ANSI_2), letter(kVK_ANSI_3), letter(kVK_ANSI_4),
            letter(kVK_ANSI_5), letter(kVK_ANSI_6), letter(kVK_ANSI_7), letter(kVK_ANSI_8),
            letter(kVK_ANSI_9), letter(kVK_ANSI_0),
            letter(kVK_ANSI_Minus), letter(kVK_ANSI_Equal),
            named("⌫", kVK_Delete, width: 1.4),
        ],
        [
            named("⇥", kVK_Tab, width: 1.4),
            letter(kVK_ANSI_Q), letter(kVK_ANSI_W), letter(kVK_ANSI_E), letter(kVK_ANSI_R),
            letter(kVK_ANSI_T), letter(kVK_ANSI_Y), letter(kVK_ANSI_U), letter(kVK_ANSI_I),
            letter(kVK_ANSI_O), letter(kVK_ANSI_P),
            letter(kVK_ANSI_LeftBracket), letter(kVK_ANSI_RightBracket),
            named("↩", kVK_Return, width: 1.4),
        ],
        [
            named("⇪", nil, width: 1.7),
            letter(kVK_ANSI_A), letter(kVK_ANSI_S), letter(kVK_ANSI_D), letter(kVK_ANSI_F),
            letter(kVK_ANSI_G), letter(kVK_ANSI_H), letter(kVK_ANSI_J), letter(kVK_ANSI_K),
            letter(kVK_ANSI_L),
            letter(kVK_ANSI_Semicolon), letter(kVK_ANSI_Quote), letter(kVK_ANSI_Backslash),
        ],
        [
            modifier("⇧", "shift", .maskShift, width: 1.4),
            letter(kVK_ISO_Section),
            letter(kVK_ANSI_Z), letter(kVK_ANSI_X), letter(kVK_ANSI_C), letter(kVK_ANSI_V),
            letter(kVK_ANSI_B), letter(kVK_ANSI_N), letter(kVK_ANSI_M),
            letter(kVK_ANSI_Comma), letter(kVK_ANSI_Period), letter(kVK_ANSI_Slash),
            modifier("⇧", "shift", .maskShift, width: 1.4),
        ],
    ]
}
