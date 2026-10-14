import AppKit
import SwiftUI

/// Shows the report before it is copied, so nobody pastes what they have not seen.
@MainActor
final class DiagnosticsWindow {
    private let makeReport: () -> DiagnosticsReport?
    private let model = DiagnosticsModel()
    private var window: NSWindow?

    init(makeReport: @escaping () -> DiagnosticsReport?) {
        self.makeReport = makeReport
    }

    /// A fresh snapshot every time it is opened.
    func show() {
        model.report = makeReport()
        if window == nil { window = build() }

        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    private func build() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Flip Diagnostics"
        window.contentMinSize = NSSize(width: 420, height: 280)

        let view = DiagnosticsView(model: model) { [weak self] in self?.refresh() }
        window.contentView = NSHostingView(rootView: view)
        window.setContentSize(NSSize(width: 640, height: 480))
        window.center()
        // Same as the settings window: otherwise it opens behind.
        window.level = .floating
        window.isReleasedWhenClosed = false

        return window
    }

    private func refresh() {
        model.report = makeReport()
    }
}

@MainActor
final class DiagnosticsModel: ObservableObject {
    @Published var report: DiagnosticsReport?
}

private struct DiagnosticsView: View {
    @ObservedObject var model: DiagnosticsModel
    let onRefresh: () -> Void

    @State private var copied = false

    var body: some View {
        VStack(spacing: 0) {
            ReportTextView(text: model.report.map(ReportStyle.attributed) ?? NSAttributedString())

            Divider()

            buttons
        }
    }

    private var buttons: some View {
        HStack {
            Button("Refresh", systemImage: "arrow.clockwise", action: onRefresh)

            Spacer()

            Button(copied ? "Copied ✓" : "Copy", action: copy)
                .keyboardShortcut(.defaultAction)
                .disabled(copied || model.report == nil)
        }
        .padding(12)
    }

    private func copy() {
        guard let report = model.report else { return }

        Diagnostics.copyToPasteboard(report.plainText)
        copied = true

        // Long enough to read, short enough that the button is not stuck.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copied = false }
    }
}

/// A wrapped line continues under its own column rather than at the left edge,
/// which a SwiftUI `Text` cannot do and a paragraph style can.
@MainActor
enum ReportStyle {
    static let font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)

    static func attributed(_ report: DiagnosticsReport) -> NSAttributedString {
        let text = NSMutableAttributedString()
        append(report.factLines + ["", DiagnosticsReport.logHeading], indent: report.factValueColumn, to: text)

        guard !report.log.isEmpty else {
            append(["(none)"], indent: 0, to: text)
            return text
        }

        for (line, entry) in zip(report.logLines, report.log) {
            append([line], indent: report.logMessageColumn, colour: entry.isError ? .systemRed : nil, to: text)
        }

        return text
    }

    private static func append(
        _ lines: [String], indent columns: Int, colour: NSColor? = nil, to text: NSMutableAttributedString
    ) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.headIndent = CGFloat(columns) * characterWidth

        let separator = text.length == 0 ? "" : "\n"
        text.append(NSAttributedString(string: separator + lines.joined(separator: "\n"), attributes: [
            .font: font,
            .foregroundColor: colour ?? NSColor.labelColor,
            .paragraphStyle: paragraph,
        ]))
    }

    /// Every character is this wide in a monospaced font.
    private static var characterWidth: CGFloat {
        ("0" as NSString).size(withAttributes: [.font: font]).width
    }
}

/// Read-only but selectable, and scrolled to the newest line on every update.
private struct ReportTextView: NSViewRepresentable {
    let text: NSAttributedString

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.drawsBackground = false
        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }

        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 8, height: 10)

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView,
              textView.textStorage?.isEqual(to: text) == false
        else { return }

        textView.textStorage?.setAttributedString(text)
        textView.scrollToEndOfDocument(nil)
    }
}
