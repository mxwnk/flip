import AppKit

/// The only visible surface Flip has, and the only way to quit it.
@MainActor
final class MenuBarItem: NSObject {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var status = Permissions.Status(accessibility: false, screenRecording: false)
    private var isPaused = false
    private var inputWorking = true
    private var availableUpdate: String?
    private let onShowSettings: () -> Void
    private let onShowUpdate: () -> Void
    private let onShowAbout: () -> Void
    private let onCopyDiagnostics: () -> Void
    private let onTogglePause: () -> Void

    init(
        onShowSettings: @escaping () -> Void,
        onShowUpdate: @escaping () -> Void,
        onShowAbout: @escaping () -> Void,
        onCopyDiagnostics: @escaping () -> Void,
        onTogglePause: @escaping () -> Void
    ) {
        self.onShowSettings = onShowSettings
        self.onShowUpdate = onShowUpdate
        self.onShowAbout = onShowAbout
        self.onCopyDiagnostics = onCopyDiagnostics
        self.onTogglePause = onTogglePause
        super.init()

        update(for: status, paused: false, inputWorking: true)
    }

    /// A switcher without Accessibility looks like a broken keyboard, so the
    /// icon carries the warning — and so does a tap that never came up, which
    /// is the same thing from the outside.
    func update(for status: Permissions.Status, paused: Bool, inputWorking: Bool) {
        self.status = status
        self.inputWorking = inputWorking
        isPaused = paused

        let symbol: String
        if paused {
            symbol = "pause.circle"
        } else if status.isComplete, inputWorking {
            symbol = "rectangle.on.rectangle"
        } else {
            symbol = "exclamationmark.triangle"
        }

        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Flip")
        image?.isTemplate = true
        item.button?.image = image
        item.button?.toolTip = paused ? "Flip is paused" : "Flip"
        item.menu = buildMenu()
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        let header = NSMenuItem(title: "Flip \(Bundle.main.shortVersion)", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        // Under the version, where anyone wondering would look. The menu bar
        // icon stays clean: it means something is wrong, and this is not.
        if let availableUpdate {
            menu.addItem(action("Update to \(availableUpdate)…", #selector(openReleasePage)))
        }

        menu.addItem(.separator())

        menu.addItem(grant("Accessibility", status.accessibility))
        menu.addItem(grant("Screen Recording", status.screenRecording))

        // Only when it is wrong: the tap working is the ordinary case and needs
        // no line, but a dead one is invisible everywhere else.
        if !inputWorking {
            let dead = NSMenuItem(title: "Keyboard shortcuts unavailable", action: nil, keyEquivalent: "")
            dead.isEnabled = false
            dead.toolTip = "The event tap could not be created. Flip keeps retrying."
            menu.addItem(dead)
        }

        if !status.isComplete {
            menu.addItem(action("Open Privacy Settings…", #selector(openPrivacySettings)))
        }

        menu.addItem(.separator())
        let pause = action(isPaused ? "Resume" : "Pause", #selector(togglePause))
        pause.state = isPaused ? .on : .off
        menu.addItem(pause)
        menu.addItem(action("Settings…", #selector(showSettings), keyEquivalent: ","))

        menu.addItem(.separator())
        menu.addItem(action("About Flip", #selector(showAbout)))
        let diagnostics = action("Copy Diagnostics", #selector(copyDiagnostics))
        diagnostics.toolTip = "Version, grants, settings and Flip's recent log, as text"
        menu.addItem(diagnostics)

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

    @objc private func togglePause() {
        onTogglePause()
    }

    @objc private func showSettings() {
        onShowSettings()
    }

    /// Rebuilt rather than mutated: the menu is cheap and rebuilding it is how
    /// every other change here already works.
    func showUpdate(available version: String?) {
        availableUpdate = version
        item.menu = buildMenu()
    }

    @objc private func openReleasePage() {
        onShowUpdate()
    }

    @objc private func showAbout() {
        onShowAbout()
    }

    @objc private func copyDiagnostics() {
        onCopyDiagnostics()
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
