import AppKit

/// The only visible surface Flip has.
///
/// Without it the app is invisible by design — no Dock icon, no window — and the
/// only way to stop it is `killall`. That became a real gap once the login agent
/// started bringing it back after every crash: there has to be a way to say stop
/// and be believed.
@MainActor
final class MenuBarItem: NSObject {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var status = Permissions.Status(accessibility: false, screenRecording: false)
    private let onShowShortcuts: () -> Void

    init(onShowShortcuts: @escaping () -> Void) {
        self.onShowShortcuts = onShowShortcuts
        super.init()

        item.button?.toolTip = "Flip"
        update(for: status)
    }

    /// Also the fastest way to see that something is wrong: a switcher whose
    /// Accessibility grant went away looks exactly like a broken keyboard.
    func update(for status: Permissions.Status) {
        self.status = status

        let symbol = status.isComplete ? "rectangle.on.rectangle" : "exclamationmark.triangle"
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Flip")
        image?.isTemplate = true
        item.button?.image = image
        item.menu = buildMenu()
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        let header = NSMenuItem(title: "Flip \(Bundle.main.shortVersion)", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        menu.addItem(grant("Accessibility", status.accessibility))
        menu.addItem(grant("Screen Recording", status.screenRecording))

        if !status.isComplete {
            menu.addItem(action("Open Privacy Settings…", #selector(openPrivacySettings)))
        }

        menu.addItem(.separator())
        menu.addItem(action("Shortcuts…", #selector(showShortcuts), keyEquivalent: ","))

        menu.addItem(.separator())
        menu.addItem(action("Quit Flip", #selector(quit), keyEquivalent: "q"))

        return menu
    }

    /// Shown rather than made actionable: the grant itself can only be given in
    /// System Settings, so a checkmark here is a report, not a control.
    private func grant(_ name: String, _ granted: Bool) -> NSMenuItem {
        let item = NSMenuItem(title: name, action: nil, keyEquivalent: "")
        item.state = granted ? .on : .off
        item.isEnabled = false

        return item
    }

    private func action(_ title: String, _ selector: Selector, keyEquivalent: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: keyEquivalent)
        item.target = self

        return item
    }

    @objc private func showShortcuts() {
        onShowShortcuts()
    }

    @objc private func openPrivacySettings() {
        let pane = status.accessibility ? "Privacy_ScreenCapture" : "Privacy_Accessibility"
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")
        else { return }

        NSWorkspace.shared.open(url)
    }

    /// A clean exit, which is exactly what the login agent's KeepAlive is set to
    /// respect: quitting on purpose has to stick, only a crash brings Flip back.
    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
