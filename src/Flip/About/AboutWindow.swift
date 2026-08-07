import AppKit
import SwiftUI

/// Same reason as the settings window: an accessory application is never the
/// active one, so ordering front without activating opens it behind everything.
@MainActor
final class AboutWindow {
    static let repository = URL(string: "https://github.com/mxwnk/flip")!

    private let onCopyDiagnostics: () -> String
    private var window: NSWindow?

    init(onCopyDiagnostics: @escaping () -> String) {
        self.onCopyDiagnostics = onCopyDiagnostics
    }

    func show() {
        if window == nil { window = build() }

        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    private func build() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 430),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "About Flip"
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true

        let host = NSHostingView(rootView: AboutView(onCopyDiagnostics: onCopyDiagnostics))
        host.sizingOptions = []
        window.contentView = host

        window.setContentSize(NSSize(width: 380, height: 430))
        window.center()
        window.isReleasedWhenClosed = false

        return window
    }
}

private struct AboutView: View {
    let onCopyDiagnostics: () -> String

    @State private var copied = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 24)

            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)

            Text("Flip")
                .font(.system(size: 26, weight: .semibold))
                .padding(.top, 12)

            Text("Version \(Bundle.main.versionDescription)")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .padding(.top, 2)
                // Selectable so a version can be pasted into a report by hand,
                // for anyone who does not want the whole diagnostic dump.
                .textSelection(.enabled)

            Text("A window switcher for macOS that gets out of the way.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 14)
                .padding(.horizontal, 32)

            Spacer(minLength: 20)

            VStack(spacing: 10) {
                Link("github.com/mxwnk/flip", destination: AboutWindow.repository)
                    .font(.system(size: 12))

                Button(copied ? "Diagnostics Copied" : "Copy Diagnostics") { copy() }
                    .disabled(copied)
            }

            Spacer(minLength: 20)

            VStack(spacing: 3) {
                Text("MIT licence")
                Text(Bundle.main.copyright)
            }
            .font(.system(size: 11))
            .foregroundStyle(.tertiary)
            .padding(.bottom, 22)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func copy() {
        Diagnostics.copyToPasteboard(onCopyDiagnostics())
        copied = true

        // Long enough to be read, short enough that the button is not stuck.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copied = false }
    }
}
