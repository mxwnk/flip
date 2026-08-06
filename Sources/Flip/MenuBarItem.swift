import AppKit

/// The only visible surface Flip has, and the only way to quit it.
@MainActor
final class MenuBarItem: NSObject {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var status = Permissions.Status(accessibility: false, screenRecording: false)
    private let onShowSettings: () -> Void

    init(onShowSettings: @escaping () -> Void) {
        self.onShowSettings = onShowSettings
        super.init()

        item.button?.toolTip = "Flip"
        update(for: status)
    }

    /// A switcher that lost Accessibility looks exactly like a broken keyboard,
    /// so the icon carries the warning.
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
        menu.addItem(action("Settings…", #selector(showSettings), keyEquivalent: ","))

        menu.addItem(.separator())
        menu.addItem(action("Quit Flip", #selector(quit), keyEquivalent: "q"))

        return menu
    }

    /// A report, not a control: grants can only be given in System Settings.
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

    @objc private func showSettings() {
        onShowSettings()
    }

    @objc private func openPrivacySettings() {
        let pane = status.accessibility ? "Privacy_ScreenCapture" : "Privacy_Accessibility"
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")
        else { return }

        NSWorkspace.shared.open(url)
    }

    /// A clean exit, which the agent's KeepAlive respects: only a crash restarts.
    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
