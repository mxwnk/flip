import Foundation

/// The report as data rather than text, so the window can mark the errors and
/// the clipboard can fence the log for an issue.
struct DiagnosticsReport: Equatable {
    struct Fact: Equatable {
        let label: String
        let value: String
    }

    struct LogLine: Equatable {
        let time: String
        let isError: Bool
        let category: String
        let message: String
    }

    var title: String
    /// Shown with a blank line between each.
    var sections: [[Fact]]
    var log: [LogLine]

    func value(of label: String) -> String? {
        sections.joined().first { $0.label == label }?.value
    }

    private static let gap = "  "

    /// Where every value starts, in characters: a wrapped one indents to here.
    var factValueColumn: Int {
        (sections.joined().map(\.label.count).max() ?? 0) + 1 + Self.gap.count
    }

    /// Where every message starts, in characters: a wrapped one indents to here.
    var logMessageColumn: Int {
        let time = log.first?.time.count ?? 0
        let category = log.map(\.category.count).max() ?? 0

        return time + Self.gap.count + 1 + Self.gap.count + category + Self.gap.count
    }

    /// The title, then every fact with its value in one column across sections.
    var factLines: [String] {
        var lines = [title]

        for section in sections {
            lines.append("")
            lines += section.map { pad($0.label + ":", to: factValueColumn) + $0.value }
        }

        return lines
    }

    /// Time, an error mark and the category each in a column of their own, so
    /// every message starts at the same place.
    var logLines: [String] {
        let categoryWidth = log.map(\.category.count).max() ?? 0

        return log.map { line in
            let prefix = line.time + Self.gap + (line.isError ? "!" : " ") + Self.gap
                + pad(line.category, to: categoryWidth) + Self.gap
            return prefix + line.message
        }
    }

    private func pad(_ text: String, to width: Int) -> String {
        text.padding(toLength: max(width, text.count), withPad: " ", startingAt: 0)
    }

    static let logHeading = "Recent log:"

    /// What Copy puts on the clipboard. The log is fenced, or GitHub collapses
    /// the columns that line it up.
    var plainText: String {
        let log = logLines.isEmpty ? ["(none)"] : ["```"] + logLines + ["```"]

        return (factLines + ["", Self.logHeading] + log).joined(separator: "\n")
    }
}
