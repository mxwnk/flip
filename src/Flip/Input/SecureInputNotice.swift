import AppKit
import SwiftUI

/// Explains, in words a user can act on, why Flip has gone deaf. Not modal: a
/// modal alert would hold up main, where every switcher action runs. Only the
/// user closes it; secure input ending turns it into the all-clear instead.
@MainActor
final class SecureInputNotice {
    private var window: NSWindow?

    func show() {
        present(SecureInputNoticeView(state: .blocked) { [weak self] in self?.dismiss() })

        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    /// Only an open notice changes; nobody needs telling that nothing is wrong.
    func showResolved() {
        guard window?.isVisible == true else { return }

        present(SecureInputNoticeView(state: .resolved) { [weak self] in self?.dismiss() })
    }

    private func dismiss() {
        window?.orderOut(nil)
    }

    private func present(_ view: SecureInputNoticeView) {
        let window = window ?? build()
        self.window = window

        let host = NSHostingView(rootView: view)
        window.contentView = host
        window.setContentSize(host.fittingSize)
        if !window.isVisible { window.center() }
    }

    private func build() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 300),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Flip can't see your keyboard"
        // Laid out like a system alert: no title, no window buttons, OK closes.
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            window.standardWindowButton(button)?.isHidden = true
        }
        // Same as the settings window: otherwise it opens behind.
        window.level = .floating
        window.isReleasedWhenClosed = false

        return window
    }
}

struct SecureInputNoticeView: View {
    enum State {
        case blocked
        case resolved
    }

    private static let blockedExplanation = "An app has turned on **Secure Input**, so macOS hides "
        + "your keystrokes from Flip. Password managers often leave it on."
    private static let resolvedExplanation = "Secure Input is off, so your shortcuts work again."

    let state: State
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            content

            Button(action: onDismiss) {
                Text("OK").frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .padding(.top, 6)
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .padding(.bottom, 16)
        .frame(width: 300)
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .blocked:
            symbol("lock.shield.fill", tint: .orange)
            title("Flip can't see your keyboard")
            explanation(Self.blockedExplanation)
        case .resolved:
            symbol("checkmark.shield.fill", tint: .green)
            title("Flip can see your keyboard again")
            explanation(Self.resolvedExplanation)
        }
    }

    private func symbol(_ name: String, tint: Color) -> some View {
        Image(systemName: name)
            .font(.system(size: 44))
            .foregroundStyle(tint)
    }

    private func title(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 14, weight: .semibold))
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Laid over the longer text, hidden, so both states are the same height
    /// and the window does not jump when one turns into the other.
    private func explanation(_ text: String) -> some View {
        ZStack(alignment: .top) {
            paragraph(Self.blockedExplanation).hidden()
            paragraph(text)
        }
    }

    /// Wraps instead of truncating, and reads the markdown a concatenated
    /// string would otherwise show as asterisks.
    private func paragraph(_ text: String) -> some View {
        Text(LocalizedStringKey(text))
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
