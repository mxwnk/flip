import CoreGraphics
import Foundation

/// The one vocabulary config.json has for modifiers. Every modifier setting is
/// an array of these, whichever combinations that setting allows.
enum ModifierKeyword: String, Codable, CaseIterable {
    case command
    case option
    case control
    case shift

    var flag: CGEventFlags {
        switch self {
        case .command: return .maskCommand
        case .option: return .maskAlternate
        case .control: return .maskControl
        case .shift: return .maskShift
        }
    }

    /// Always this order, whatever order it was read in, so a save that changes
    /// nothing leaves the file alone.
    static func spelling(_ flags: CGEventFlags) -> [ModifierKeyword] {
        allCases.filter { flags.contains($0.flag) }
    }

    static func flags(of keywords: [ModifierKeyword]) -> CGEventFlags {
        CGEventFlags(keywords.map(\.flag))
    }
}

/// A closed set of modifier combinations that reads and writes itself as
/// keywords. The flags are what identifies a case in the file, so which case is
/// named in the code and how it is spelled on disk stay independent.
protocol ModifierSet: CaseIterable {
    var flags: CGEventFlags { get }
}

extension ModifierSet {
    static func decoded(from decoder: Decoder) throws -> Self {
        let flags = ModifierKeyword.flags(of: try [ModifierKeyword](from: decoder))
        guard let match = allCases.first(where: { $0.flags == flags }) else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: unsupported(flags))
            )
        }

        return match
    }

    func encoded(to encoder: Encoder) throws {
        try ModifierKeyword.spelling(flags).encode(to: encoder)
    }

    private static func unsupported(_ flags: CGEventFlags) -> String {
        let spelling = ModifierKeyword.spelling(flags).map(\.rawValue).joined(separator: " ")

        return "\(Self.self) does not offer \(spelling)"
    }
}
