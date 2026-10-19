import AppKit
import SwiftUI
import ServiceManagement

@main
struct DictationMenuApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()

    private let statusHeaderItem = NSMenuItem(title: "Dictation: Checking…", action: nil, keyEquivalent: "")
    private let toggleMenuItem = NSMenuItem(title: "Turn Dictation On", action: #selector(handleToggleDictation), keyEquivalent: "")
    private let customizeShortcutItem = NSMenuItem(title: "Customize Shortcut…", action: #selector(handleCustomizeShortcut), keyEquivalent: "")
    private let openSystemSettingsItem = NSMenuItem(title: "Open Dictation Settings…", action: #selector(handleOpenSystemSettings), keyEquivalent: ",")
    private let launchAtLoginItem = NSMenuItem(title: "Launch at Login", action: #selector(handleToggleLaunchAtLogin), keyEquivalent: "")
    private let quitMenuItem = NSMenuItem(title: "Quit DictationMenu", action: #selector(handleQuit), keyEquivalent: "q")

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusBarItem()
        setupMenu()
        setupCallbacks()
        updateUI(isEnabled: DictationController.shared.refreshState())
    }

    private func setupStatusBarItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.menu = menu
    }

    private func setupMenu() {
        menu.delegate = self

        statusHeaderItem.isEnabled = false
        menu.addItem(statusHeaderItem)
        menu.addItem(.separator())

        toggleMenuItem.target = self
        menu.addItem(toggleMenuItem)

        customizeShortcutItem.target = self
        menu.addItem(customizeShortcutItem)

        menu.addItem(.separator())

        openSystemSettingsItem.target = self
        menu.addItem(openSystemSettingsItem)

        launchAtLoginItem.target = self
        updateLaunchAtLoginState()
        menu.addItem(launchAtLoginItem)

        menu.addItem(.separator())

        quitMenuItem.target = self
        menu.addItem(quitMenuItem)

        updateShortcutDisplay(GlobalHotkeyManager.shared.currentCombo)
    }

    private func setupCallbacks() {
        DictationController.shared.onStateChanged = { [weak self] isEnabled in
            DispatchQueue.main.async {
                self?.updateUI(isEnabled: isEnabled)
            }
        }

        GlobalHotkeyManager.shared.onHotKeyPressed = { [weak self] in
            let newState = DictationController.shared.toggleDictation()
            self?.updateUI(isEnabled: newState)
            self?.showHUDFeedback(isEnabled: newState)
        }

        GlobalHotkeyManager.shared.onShortcutChanged = { [weak self] newCombo in
            DispatchQueue.main.async {
                self?.updateShortcutDisplay(newCombo)
            }
        }
    }

    // MARK: - NSMenuDelegate

    func menuWillOpen(_ menu: NSMenu) {
        let current = DictationController.shared.refreshState()
        updateUI(isEnabled: current)
        updateLaunchAtLoginState()
    }

    // MARK: - UI Updates

    private func makeStatusBarIcon(symbolName: String, accessibilityDescription: String) -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        guard let baseSymbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: accessibilityDescription)?
            .withSymbolConfiguration(config) else {
            return nil
        }

        let canvasSize = NSSize(width: 18, height: 18)
        let fixedImage = NSImage(size: canvasSize, flipped: false) { canvasRect in
            let symbolSize = baseSymbol.size
            let drawRect = NSRect(
                x: (canvasRect.width - symbolSize.width) / 2.0,
                y: (canvasRect.height - symbolSize.height) / 2.0,
                width: symbolSize.width,
                height: symbolSize.height
            )
            baseSymbol.draw(in: drawRect)
            return true
        }
        fixedImage.isTemplate = true
        return fixedImage
    }

    private func updateUI(isEnabled: Bool) {
        if let button = statusItem.button {
            let symbolName = isEnabled ? "mic.fill" : "mic.slash"
            let accessibilityDesc = isEnabled ? "Dictation Enabled" : "Dictation Disabled"
            if let image = makeStatusBarIcon(symbolName: symbolName, accessibilityDescription: accessibilityDesc) {
                button.image = image
                button.imagePosition = .imageOnly
            } else {
                button.title = isEnabled ? "🎙️" : "🔇"
            }
            button.toolTip = "System Dictation: \(isEnabled ? "On" : "Off") (\(GlobalHotkeyManager.shared.currentCombo.displayString))"
        }

        // Update Menu Items
        let statusDot = isEnabled ? "🟢" : "⚪️"
        statusHeaderItem.title = "\(statusDot) System Dictation is \(isEnabled ? "On" : "Off")"
        toggleMenuItem.title = isEnabled ? "Turn Dictation Off" : "Turn Dictation On"
    }

    private func updateShortcutDisplay(_ combo: KeyCombo) {
        toggleMenuItem.keyEquivalent = combo.keyEquivalentString
        toggleMenuItem.keyEquivalentModifierMask = combo.nsEventModifierFlags
        customizeShortcutItem.title = "Customize Shortcut (\(combo.displayString))…"
        updateUI(isEnabled: DictationController.shared.isDictationEnabled)
    }

    private func updateLaunchAtLoginState() {
        let status = SMAppService.mainApp.status
        launchAtLoginItem.state = (status == .enabled) ? .on : .off
    }

    private func showHUDFeedback(isEnabled: Bool) {
        NSSound.Pop?.play()
    }

    // MARK: - Actions

    @objc private func handleToggleDictation() {
        let newState = DictationController.shared.toggleDictation()
        updateUI(isEnabled: newState)
    }

    @objc private func handleCustomizeShortcut() {
        ShortcutRecorderWindowController.shared.showRecorder()
    }

    @objc private func handleOpenSystemSettings() {
        DictationController.shared.openDictationSystemSettings()
    }

    @objc private func handleToggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
            updateLaunchAtLoginState()
        } catch {
            let alert = NSAlert()
            alert.messageText = "Could Not Update Launch at Login"
            alert.informativeText = "Make sure DictationMenu.app is placed in /Applications to manage Launch at Login.\n\nDetails: \(error.localizedDescription)"
            alert.alertStyle = .warning
            alert.runModal()
        }
    }

    @objc private func handleQuit() {
        NSApplication.shared.terminate(nil)
    }
}

private extension NSSound {
    static var Pop: NSSound? {
        NSSound(named: NSSound.Name("Pop")) ?? NSSound(named: NSSound.Name("Tink"))
    }
}
