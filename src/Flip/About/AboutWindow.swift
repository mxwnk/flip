import AppKit
import SwiftUI

/// Same as the settings window: an accessory application is never the active
/// one, so ordering front is not enough on its own.
@MainActor
final class AboutWindow {
    static let repository = URL(string: "https://github.com/mxwnk/flip")!

    private let onShowDiagnostics: () -> Void
    private var window: NSWindow?

    init(onShowDiagnostics: @escaping () -> Void) {
        self.onShowDiagnostics = onShowDiagnostics
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

        let host = NSHostingView(rootView: AboutView(onShowDiagnostics: onShowDiagnostics))
        host.sizingOptions = []
        window.contentView = host

        window.setContentSize(NSSize(width: 380, height: 430))
        window.center()
        // Same as the settings window: otherwise it opens behind.
        window.level = .floating

        window.isReleasedWhenClosed = false

        return window
    }
}

private struct AboutView: View {
    let onShowDiagnostics: () -> Void

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
                // Selectable, for pasting a version without the whole dump.
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

                Button("Show Diagnostics…", action: onShowDiagnostics)
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
}
