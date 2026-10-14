import AppKit

/// The only visible surface Flip has, and the only way to quit it.
@MainActor
final class MenuBarItem: NSObject {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var status = Permissions.Status(accessibility: false, screenRecording: false)
    private var isPaused = false
    private var inputWorking = true
    private var canReadWindowIDs = true
    private var availableUpdate: String?
    private var layouts: [WindowLayout] = []
    private var layoutLeader = ModifierChoice.optionControl.label
    private var isSecureInputOn = false
    private let onShowSettings: () -> Void
    private let onShowUpdate: () -> Void
    private let onShowAbout: () -> Void
    private let onShowDiagnostics: () -> Void
    private let onTogglePause: () -> Void
    private let onApplyLayout: (UUID) -> Void
    private let onExplainSecureInput: () -> Void

    init(
        onShowSettings: @escaping () -> Void,
        onShowUpdate: @escaping () -> Void,
        onShowAbout: @escaping () -> Void,
        onShowDiagnostics: @escaping () -> Void,
        onTogglePause: @escaping () -> Void,
        onApplyLayout: @escaping (UUID) -> Void,
        onExplainSecureInput: @escaping () -> Void
    ) {
        self.onShowSettings = onShowSettings
        self.onShowUpdate = onShowUpdate
        self.onShowAbout = onShowAbout
        self.onShowDiagnostics = onShowDiagnostics
        self.onTogglePause = onTogglePause
        self.onApplyLayout = onApplyLayout
        self.onExplainSecureInput = onExplainSecureInput
        super.init()

        refresh()
    }

    /// A switcher without Accessibility looks like a broken keyboard, so the
    /// icon carries the warning — and so does a tap that never came up, which
    /// is the same thing from the outside.
    func update(
        for status: Permissions.Status,
        paused: Bool,
        inputWorking: Bool,
        canReadWindowIDs: Bool,
        layouts: [WindowLayout],
        layoutLeader: String
    ) {
        self.status = status
        self.inputWorking = inputWorking
        self.canReadWindowIDs = canReadWindowIDs
        self.layouts = layouts
        self.layoutLeader = layoutLeader
        isPaused = paused
        refresh()
    }

    /// Rebuilt rather than mutated: the menu is cheap and rebuilding it is how
    /// every other change here already works.
    func showSecureInput(isOn: Bool) {
        isSecureInputOn = isOn
        refresh()
    }

    private func refresh() {
        let symbol: String
        if isPaused {
            symbol = "pause.circle"
        } else if !status.isComplete || !inputWorking || !canReadWindowIDs {
            symbol = "exclamationmark.triangle"
        } else if isSecureInputOn {
            // Not a fault in Flip, and the lock is what macOS itself shows for it.
            symbol = "lock.shield"
        } else {
            symbol = "rectangle.on.rectangle"
        }

        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Flip")
        image?.isTemplate = true
        item.button?.image = image
        item.button?.toolTip = isPaused ? "Flip is paused" : "Flip"
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
        // First, because nothing else matters if windows have no ids.
        if !canReadWindowIDs {
            let unsupported = NSMenuItem(
                title: "Not supported on this macOS", action: nil, keyEquivalent: ""
            )
            unsupported.isEnabled = false
            unsupported.toolTip = "Flip needs a private accessibility symbol this system does not export."
            menu.addItem(unsupported)
        }

        if !inputWorking {
            let dead = NSMenuItem(title: "Keyboard shortcuts unavailable", action: nil, keyEquivalent: "")
            dead.isEnabled = false
            dead.toolTip = "The event tap could not be created. Flip keeps retrying."
            menu.addItem(dead)
        }

        if isSecureInputOn {
            menu.addItem(action("Secure Input is blocking Flip…", #selector(explainSecureInput)))
        }

        if !status.isComplete {
            menu.addItem(action("Open Privacy Settings…", #selector(openPrivacySettings)))
        }

        if !layouts.isEmpty {
            menu.addItem(.separator())
            let layoutsItem = NSMenuItem(title: "Layouts", action: nil, keyEquivalent: "")
            let layoutsSubmenu = NSMenu()
            for layout in layouts {
                let item = NSMenuItem(
                    title: layout.name,
                    action: #selector(applyLayoutAction(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = layout.id
                if let key = layout.key, !key.isEmpty {
                    item.toolTip = "Shortcut: \(layoutLeader)\(KeyboardLayout.symbol(forBinding: key))"
                }
                layoutsSubmenu.addItem(item)
            }
            layoutsItem.submenu = layoutsSubmenu
            menu.addItem(layoutsItem)
        }

        menu.addItem(.separator())
        let pause = action(isPaused ? "Resume" : "Pause", #selector(togglePause))
        pause.state = isPaused ? .on : .off
        menu.addItem(pause)
        menu.addItem(action("Settings…", #selector(showSettings), keyEquivalent: ","))

        menu.addItem(.separator())
        menu.addItem(action("About Flip", #selector(showAbout)))
        let diagnostics = action("Diagnostics…", #selector(showDiagnostics))
        diagnostics.toolTip = "Version, grants, settings and Flip's recent log, as text"
        menu.addItem(diagnostics)

        menu.addItem(.separator())
        menu.addItem(action("Quit Flip", #selector(quit), keyEquivalent: "q"))

        return menu
    }

    @objc private func applyLayoutAction(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        onApplyLayout(id)
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

    @objc private func explainSecureInput() {
        onExplainSecureInput()
    }

    @objc private func togglePause() {
        onTogglePause()
    }

    @objc private func showSettings() {
        onShowSettings()
    }

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

    @objc private func showDiagnostics() {
        onShowDiagnostics()
    }

    @objc private func openPrivacySettings() {
        let pane = status.accessibility ? "Privacy_ScreenCapture" : "Privacy_Accessibility"
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")
        else { return }

        NSWorkspace.shared.open(url)
    }

    /// The login agent has no KeepAlive, so nothing restarts Flip before the
    /// next login.
    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
