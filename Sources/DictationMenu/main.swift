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

    // Primary Toggle Items
    private let statusHeaderItem = NSMenuItem(title: "Dictation: Checking…", action: nil, keyEquivalent: "")
    private let toggleMenuItem = NSMenuItem(title: "Turn Dictation On", action: #selector(handleToggleDictation), keyEquivalent: "")

    // System Dictation Settings Items
    private let languagesMenuItem = NSMenuItem(title: "Languages", action: nil, keyEquivalent: "")
    private let languagesSubmenu = NSMenu(title: "Languages")
    private let addLanguagesSubmenu = NSMenu(title: "Add / Toggle More Languages")

    private let microphoneMenuItem = NSMenuItem(title: "Microphone Source", action: nil, keyEquivalent: "")
    private let microphoneSubmenu = NSMenu(title: "Microphone Source")

    private let systemShortcutMenuItem = NSMenuItem(title: "Dictation Shortcut", action: nil, keyEquivalent: "")
    private let systemShortcutSubmenu = NSMenu(title: "Dictation Shortcut")

    private let autoPunctuationMenuItem = NSMenuItem(title: "Auto-punctuation", action: #selector(handleToggleAutoPunctuation), keyEquivalent: "")

    // App Hotkey & Preferences
    private let customizeShortcutItem = NSMenuItem(title: "Toggle Dictation Hotkey…", action: #selector(handleCustomizeShortcut), keyEquivalent: "")
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

        menu.addItem(.separator())

        // 1. Languages Submenu
        languagesMenuItem.submenu = languagesSubmenu
        menu.addItem(languagesMenuItem)

        // 2. Microphone Source Submenu
        microphoneMenuItem.submenu = microphoneSubmenu
        menu.addItem(microphoneMenuItem)

        // 3. System "Start Dictation" Shortcut Submenu
        systemShortcutMenuItem.submenu = systemShortcutSubmenu
        menu.addItem(systemShortcutMenuItem)

        // 4. Auto-punctuation Toggle
        autoPunctuationMenuItem.target = self
        menu.addItem(autoPunctuationMenuItem)

        menu.addItem(.separator())

        // Global Hotkey to Toggle Dictation On/Off
        customizeShortcutItem.target = self
        menu.addItem(customizeShortcutItem)

        openSystemSettingsItem.target = self
        menu.addItem(openSystemSettingsItem)

        launchAtLoginItem.target = self
        updateLaunchAtLoginState()
        menu.addItem(launchAtLoginItem)

        menu.addItem(.separator())

        quitMenuItem.target = self
        menu.addItem(quitMenuItem)

        updateShortcutDisplay(GlobalHotkeyManager.shared.currentCombo)
        rebuildSettingsMenus()
    }

    private func setupCallbacks() {
        DictationController.shared.onStateChanged = { [weak self] isEnabled in
            DispatchQueue.main.async {
                self?.updateUI(isEnabled: isEnabled)
            }
        }

        DictationController.shared.onSettingsChanged = { [weak self] in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.updateUI(isEnabled: DictationController.shared.isDictationEnabled)
                self.rebuildSettingsMenus()
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
        rebuildSettingsMenus()
        updateLaunchAtLoginState()
    }

    // MARK: - Dynamic Submenus Construction

    private func rebuildSettingsMenus() {
        // 1. Auto-punctuation state
        let autoPunct = DictationController.shared.queryAutoPunctuationEnabled()
        autoPunctuationMenuItem.state = autoPunct ? .on : .off

        // 2. Languages Submenu
        rebuildLanguagesMenu()

        // 3. Microphone Source Submenu
        rebuildMicrophoneMenu()

        // 4. System Dictation Shortcut Submenu
        rebuildSystemShortcutMenu()
    }

    private func rebuildLanguagesMenu() {
        languagesSubmenu.removeAllItems()
        addLanguagesSubmenu.removeAllItems()

        let allLanguages = DictationController.shared.availableLanguages()
        let enabledLanguages = allLanguages.filter { $0.isEnabled }
        let disabledLanguages = allLanguages.filter { !$0.isEnabled }

        if enabledLanguages.count == 1, let single = enabledLanguages.first {
            languagesMenuItem.title = "Languages: \(single.displayTitle)"
        } else if enabledLanguages.count > 1 {
            languagesMenuItem.title = "Languages (\(enabledLanguages.count) Enabled)"
        } else {
            languagesMenuItem.title = "Languages"
        }

        let activeHeader = NSMenuItem(title: "Enabled Languages", action: nil, keyEquivalent: "")
        activeHeader.isEnabled = false
        languagesSubmenu.addItem(activeHeader)

        for lang in enabledLanguages {
            let item = NSMenuItem(
                title: lang.displayTitle,
                action: #selector(handleToggleLanguage(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.state = .on
            item.representedObject = lang.localeIdentifier
            // If only 1 language is enabled, keep it checked; clicking will beep as at least one is required
            languagesSubmenu.addItem(item)
        }

        if !disabledLanguages.isEmpty {
            languagesSubmenu.addItem(.separator())

            let moreItem = NSMenuItem(title: "Add Language", action: nil, keyEquivalent: "")
            moreItem.submenu = addLanguagesSubmenu
            languagesSubmenu.addItem(moreItem)

            for lang in disabledLanguages {
                let item = NSMenuItem(
                    title: lang.displayTitle,
                    action: #selector(handleToggleLanguage(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.state = .off
                item.representedObject = lang.localeIdentifier
                addLanguagesSubmenu.addItem(item)
            }
        }
    }

    private func rebuildMicrophoneMenu() {
        microphoneSubmenu.removeAllItems()

        let mics = DictationController.shared.availableMicrophones()
        if let selectedMic = mics.first(where: { $0.isSelected }) {
            microphoneMenuItem.title = "Microphone: \(selectedMic.displayTitle)"
        } else {
            microphoneMenuItem.title = "Microphone Source"
        }

        for (index, mic) in mics.enumerated() {
            if index == 1 {
                microphoneSubmenu.addItem(.separator())
            }
            let item = NSMenuItem(
                title: mic.displayTitle,
                action: #selector(handleSelectMicrophone(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.state = mic.isSelected ? .on : .off
            item.representedObject = mic
            microphoneSubmenu.addItem(item)
        }
    }

    private func rebuildSystemShortcutMenu() {
        systemShortcutSubmenu.removeAllItems()

        let currentPreset = DictationController.shared.currentSystemDictationShortcut()
        systemShortcutMenuItem.title = "Shortcut: \(currentPreset.displayTitle)"

        let standardPresets: [(title: String, tag: Int, preset: SystemDictationShortcutPreset)] = [
            ("Press 🎤 (Dictation Key)", 1, .pressMicrophoneKey),
            ("Press Control Key Twice", 2, .pressControlTwice),
            ("Press 🌐 / Fn Key Twice", 3, .pressFnTwice),
            ("Press Right Command Key Twice", 4, .pressRightCommandTwice),
            ("Press Left Command Key Twice", 5, .pressLeftCommandTwice),
            ("Press Either Command Key Twice", 6, .pressEitherCommandTwice)
        ]

        for entry in standardPresets {
            if entry.tag == 2 {
                systemShortcutSubmenu.addItem(.separator())
            }
            let item = NSMenuItem(
                title: entry.title,
                action: #selector(handleSelectSystemShortcutPreset(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.tag = entry.tag
            item.state = (currentPreset == entry.preset) ? .on : .off
            systemShortcutSubmenu.addItem(item)
        }

        systemShortcutSubmenu.addItem(.separator())

        // Show current or most recent custom shortcut if available
        if case .custom(_, _, _, let disp) = currentPreset {
            let customItem = NSMenuItem(
                title: "Custom (\(disp))",
                action: #selector(handleSelectSystemShortcutPreset(_:)),
                keyEquivalent: ""
            )
            customItem.target = self
            customItem.tag = 8
            customItem.state = .on
            systemShortcutSubmenu.addItem(customItem)
        } else if let recent = DictationController.shared.mostRecentCustomSystemDictationShortcut(),
                  case .custom(_, _, _, let disp) = recent {
            let customItem = NSMenuItem(
                title: "Custom (\(disp))",
                action: #selector(handleSelectSystemShortcutPreset(_:)),
                keyEquivalent: ""
            )
            customItem.target = self
            customItem.tag = 8
            customItem.state = .off
            systemShortcutSubmenu.addItem(customItem)
        }

        let customizeItem = NSMenuItem(
            title: "Customize Dictation Shortcut…",
            action: #selector(handleCustomizeSystemDictationShortcut),
            keyEquivalent: ""
        )
        customizeItem.target = self
        systemShortcutSubmenu.addItem(customizeItem)

        systemShortcutSubmenu.addItem(.separator())

        let offItem = NSMenuItem(
            title: "Off",
            action: #selector(handleSelectSystemShortcutPreset(_:)),
            keyEquivalent: ""
        )
        offItem.target = self
        offItem.tag = 9
        offItem.state = (currentPreset == .off) ? .on : .off
        systemShortcutSubmenu.addItem(offItem)
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

        let statusDot = isEnabled ? "🟢" : "⚪️"
        statusHeaderItem.title = "\(statusDot) System Dictation is \(isEnabled ? "On" : "Off")"
        toggleMenuItem.title = isEnabled ? "Turn Dictation Off" : "Turn Dictation On"
    }

    private func updateShortcutDisplay(_ combo: KeyCombo) {
        toggleMenuItem.keyEquivalent = combo.keyEquivalentString
        toggleMenuItem.keyEquivalentModifierMask = combo.nsEventModifierFlags
        customizeShortcutItem.title = "Toggle On/Off Hotkey (\(combo.displayString))…"
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

    @objc private func handleToggleAutoPunctuation() {
        let enabled = DictationController.shared.toggleAutoPunctuation()
        autoPunctuationMenuItem.state = enabled ? .on : .off
    }

    @objc private func handleToggleLanguage(_ sender: NSMenuItem) {
        guard let localeID = sender.representedObject as? String else { return }
        DictationController.shared.toggleLanguage(localeID)
        rebuildLanguagesMenu()
    }

    @objc private func handleSelectMicrophone(_ sender: NSMenuItem) {
        guard let mic = sender.representedObject as? DictationMicrophoneOption else { return }
        DictationController.shared.setPreferredMicrophone(identifier: mic.identifier, name: mic.name)
        rebuildMicrophoneMenu()
    }

    @objc private func handleSelectSystemShortcutPreset(_ sender: NSMenuItem) {
        switch sender.tag {
        case 1:
            DictationController.shared.setSystemDictationShortcut(.pressMicrophoneKey)
        case 2:
            DictationController.shared.setSystemDictationShortcut(.pressControlTwice)
        case 3:
            DictationController.shared.setSystemDictationShortcut(.pressFnTwice)
        case 4:
            DictationController.shared.setSystemDictationShortcut(.pressRightCommandTwice)
        case 5:
            DictationController.shared.setSystemDictationShortcut(.pressLeftCommandTwice)
        case 6:
            DictationController.shared.setSystemDictationShortcut(.pressEitherCommandTwice)
        case 8:
            if let recent = DictationController.shared.mostRecentCustomSystemDictationShortcut() {
                DictationController.shared.setSystemDictationShortcut(recent)
            }
        case 9:
            DictationController.shared.setSystemDictationShortcut(.off)
        default:
            break
        }
        rebuildSystemShortcutMenu()
    }

    @objc private func handleCustomizeSystemDictationShortcut() {
        SystemDictationShortcutRecorderWindowController.shared.showRecorder()
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

