import Foundation
import Carbon
import AppKit
import Darwin
import ObjectiveC

// MARK: - Models for Dictation Settings

struct DictationLanguageOption: Identifiable, Equatable {
    let localeIdentifier: String
    let displayTitle: String
    let isEnabled: Bool
    var id: String { localeIdentifier }
}

struct DictationMicrophoneOption: Identifiable, Equatable {
    /// `nil` represents "Automatic (<Device Name>)"
    let identifier: String?
    let name: String?
    let displayTitle: String
    let isSelected: Bool
    var id: String { identifier ?? "__AUTOMATIC__" }
}

enum SystemDictationShortcutPreset: Equatable {
    case pressMicrophoneKey
    case pressFnTwice
    case pressRightCommandTwice
    case pressLeftCommandTwice
    case pressEitherCommandTwice
    case pressControlTwice
    case custom(keyChar: UInt16, virtualKey: UInt16, modifiers: UInt, displayString: String)
    case off

    var displayTitle: String {
        switch self {
        case .pressMicrophoneKey:
            return "Press 🎤 (Dictation Key)"
        case .pressFnTwice:
            return "Press 🌐 / Fn Key Twice"
        case .pressRightCommandTwice:
            return "Press Right Command Key Twice"
        case .pressLeftCommandTwice:
            return "Press Left Command Key Twice"
        case .pressEitherCommandTwice:
            return "Press Either Command Key Twice"
        case .pressControlTwice:
            return "Press Control Key Twice"
        case .custom(_, _, _, let display):
            return "Custom (\(display))"
        case .off:
            return "Off"
        }
    }
}

/// Manages reading and updating all macOS System Dictation settings across:
/// - `com.apple.assistant.support` (`"Dictation Enabled"`, `"Dictation Auto Punctuation Enabled"`)
/// - `SODictationPreferences` & `SOSRLanguageItem` & `SOMicrophonePopUpButton` (`SpeechObjects.framework` / `DictationServices.framework`)
/// - Carbon Text Input Source (`com.apple.inputmethod.ironwood`)
/// - `com.apple.hitoolbox` (`"AppleDictationAutoEnable"`)
/// - `com.apple.speech.recognition.AppleSpeechRecognition.prefs`
final class DictationController: ObservableObject {
    static let shared = DictationController()

    private let dictationInputSourceID = "com.apple.inputmethod.ironwood"
    private let assistantSupportDomain = "com.apple.assistant.support" as CFString
    private let assistantDictationKey = "Dictation Enabled" as CFString
    private let assistantAutoPunctuationKey = "Dictation Auto Punctuation Enabled" as CFString

    private let hitoolboxDomain = "com.apple.hitoolbox" as CFString
    private let autoEnableKey = "AppleDictationAutoEnable" as CFString

    private let speechPrefsDomain = "com.apple.speech.recognition.AppleSpeechRecognition.prefs" as CFString
    private let masterEnabledKey = "DictationIMMasterDictationEnabled" as CFString
    private let introPresentedKey = "DictationIMIntroMessagePresented" as CFString
    private let allowHotKeyKey = "DictationIMAllowEnablingViaHotKey" as CFString
    private let visibleLocalesKey = "VisibleNetworkSRLocaleIdentifiers" as CFString

    @Published private(set) var isDictationEnabled: Bool = false
    @Published private(set) var isAutoPunctuationEnabled: Bool = true

    var onStateChanged: ((Bool) -> Void)?
    var onSettingsChanged: (() -> Void)?

    private init() {
        // Load SpeechObjects & DictationServices for native Dictation settings management
        dlopen("/System/Library/PrivateFrameworks/SpeechObjects.framework/SpeechObjects", RTLD_NOW)
        dlopen("/System/Library/PrivateFrameworks/SpeechObjects.framework/Versions/A/Frameworks/DictationServices.framework/DictationServices", RTLD_NOW)

        refreshState()
        setupNotifications()
    }

    deinit {
        let darwinCenter = CFNotificationCenterGetDarwinNotifyCenter()
        CFNotificationCenterRemoveEveryObserver(darwinCenter, Unmanaged.passUnretained(self).toOpaque())
    }

    // MARK: - 1. Dictation On/Off

    /// Queries the current system Dictation state from `com.apple.assistant.support` / `SODictationPreferences`.
    @discardableResult
    func refreshState() -> Bool {
        let current = querySystemDictationState()
        if isDictationEnabled != current {
            isDictationEnabled = current
        }
        let autoPunct = queryAutoPunctuationEnabled()
        if isAutoPunctuationEnabled != autoPunct {
            isAutoPunctuationEnabled = autoPunct
        }
        onStateChanged?(current)
        return current
    }

    /// Toggles system Dictation on or off and returns the new state.
    @discardableResult
    func toggleDictation() -> Bool {
        let targetState = !querySystemDictationState()
        setDictationEnabled(targetState)
        return isDictationEnabled
    }

    /// Explicitly enables or disables macOS System Dictation and broadcasts system-wide notifications.
    func setDictationEnabled(_ enabled: Bool) {
        let cfBool: CFBoolean = enabled ? kCFBooleanTrue : kCFBooleanFalse
        let intValue: Int = enabled ? 1 : 0

        // 1. Update com.apple.assistant.support -> "Dictation Enabled"
        CFPreferencesSetAppValue(assistantDictationKey, cfBool, assistantSupportDomain)
        CFPreferencesAppSynchronize(assistantSupportDomain)

        // 2. Update com.apple.speech.recognition.AppleSpeechRecognition.prefs
        CFPreferencesSetAppValue(masterEnabledKey, cfBool, speechPrefsDomain)
        if enabled {
            CFPreferencesSetAppValue(introPresentedKey, kCFBooleanTrue, speechPrefsDomain)
            CFPreferencesSetAppValue(allowHotKeyKey, kCFBooleanTrue, speechPrefsDomain)
        }
        CFPreferencesAppSynchronize(speechPrefsDomain)

        // 3. Update com.apple.hitoolbox -> "AppleDictationAutoEnable"
        CFPreferencesSetAppValue(autoEnableKey, intValue as CFNumber, hitoolboxDomain)
        CFPreferencesAppSynchronize(hitoolboxDomain)

        // 4. Enable or disable the Carbon Text Input Source (com.apple.inputmethod.ironwood)
        if let inputSource = findDictationInputSource() {
            if enabled {
                TISEnableInputSource(inputSource)
                TISSelectInputSource(inputSource)
            } else {
                TISDisableInputSource(inputSource)
            }
        }

        // 5. Post Darwin notifications so AssistantServices / AFPreferences / corespeechd reload immediately
        postAssistantDarwinNotifications()

        // 6. Post Distributed notifications so System Settings (KeyboardSettings.appex) and DictationIM update immediately
        let dnc = DistributedNotificationCenter.default()
        dnc.postNotificationName(
            NSNotification.Name("DictationIMNotificationEnabledStateChanged"),
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
        dnc.postNotificationName(
            NSNotification.Name("AppleDictationPreferencesChangedNotification"),
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )

        // 7. Refresh and notify UI
        let updated = querySystemDictationState()
        isDictationEnabled = updated
        onStateChanged?(updated)
        onSettingsChanged?()
    }

    // MARK: - 2. Auto-Punctuation

    func queryAutoPunctuationEnabled() -> Bool {
        CFPreferencesAppSynchronize(assistantSupportDomain)
        var exists = DarwinBoolean(false)
        let val = CFPreferencesGetAppBooleanValue(
            assistantAutoPunctuationKey,
            assistantSupportDomain,
            &exists
        )
        if exists.boolValue {
            return val
        }

        if let prefs = sharedSODictationPreferences() {
            let sel = NSSelectorFromString("dictationAutoPunctuationEnabled")
            if let imp = prefs.method(for: sel) {
                typealias GetBoolFn = @convention(c) (AnyObject, Selector) -> Bool
                let fn = unsafeBitCast(imp, to: GetBoolFn.self)
                return fn(prefs, sel)
            }
        }
        return true
    }

    @discardableResult
    func toggleAutoPunctuation() -> Bool {
        let next = !queryAutoPunctuationEnabled()
        setAutoPunctuationEnabled(next)
        return isAutoPunctuationEnabled
    }

    func setAutoPunctuationEnabled(_ enabled: Bool) {
        let cfBool: CFBoolean = enabled ? kCFBooleanTrue : kCFBooleanFalse
        CFPreferencesSetAppValue(assistantAutoPunctuationKey, cfBool, assistantSupportDomain)
        CFPreferencesAppSynchronize(assistantSupportDomain)

        if let prefs = sharedSODictationPreferences() {
            let sel = NSSelectorFromString("setDictationAutoPunctuationEnabled:")
            if let imp = prefs.method(for: sel) {
                typealias SetBoolFn = @convention(c) (AnyObject, Selector, Bool) -> Void
                let fn = unsafeBitCast(imp, to: SetBoolFn.self)
                fn(prefs, sel, enabled)
            }
        }

        postAssistantDarwinNotifications()

        let dnc = DistributedNotificationCenter.default()
        dnc.postNotificationName(
            NSNotification.Name("DictationIMNotificationEnabledStateChanged"),
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )

        isAutoPunctuationEnabled = queryAutoPunctuationEnabled()
        onSettingsChanged?()
    }

    // MARK: - 3. Microphone Source

    func availableMicrophones() -> [DictationMicrophoneOption] {
        let currentPrefMicID = currentPreferredMicrophoneIdentifier()

        guard let micBtnCls = NSClassFromString("SOMicrophonePopUpButton") as? NSPopUpButton.Type else {
            return [
                DictationMicrophoneOption(
                    identifier: nil,
                    name: nil,
                    displayTitle: "Automatic",
                    isSelected: currentPrefMicID == nil
                )
            ]
        }

        let btn = micBtnCls.init(frame: .zero)
        let buildSel = NSSelectorFromString("buildPopUpButton")
        if btn.responds(to: buildSel) {
            _ = btn.perform(buildSel)
        }

        let idSel = NSSelectorFromString("selectedMicrophoneIdentifier")
        let nameSel = NSSelectorFromString("selectedMicrophoneName")

        var results: [DictationMicrophoneOption] = []
        let items = btn.itemArray
        for i in 0..<items.count {
            let item = items[i]
            if item.isSeparatorItem { continue }

            btn.selectItem(at: i)
            let micID = btn.responds(to: idSel) ? (btn.perform(idSel)?.takeUnretainedValue() as? String) : nil
            let micName = btn.responds(to: nameSel) ? (btn.perform(nameSel)?.takeUnretainedValue() as? String) : nil

            let isSelected: Bool
            if i == 0 || micID == nil {
                isSelected = (currentPrefMicID == nil)
            } else {
                isSelected = (currentPrefMicID == micID)
            }

            results.append(
                DictationMicrophoneOption(
                    identifier: micID,
                    name: micName,
                    displayTitle: item.title,
                    isSelected: isSelected
                )
            )
        }

        if results.isEmpty {
            results.append(
                DictationMicrophoneOption(
                    identifier: nil,
                    name: nil,
                    displayTitle: "Automatic",
                    isSelected: true
                )
            )
        }
        return results
    }

    func currentPreferredMicrophoneIdentifier() -> String? {
        CFPreferencesAppSynchronize(speechPrefsDomain)
        if let prefs = sharedSODictationPreferences() {
            let sel = NSSelectorFromString("preferredMicrophoneIdentifier")
            if prefs.responds(to: sel),
               let id = prefs.perform(sel)?.takeUnretainedValue() as? String,
               !id.isEmpty {
                return id
            }
        }
        return nil
    }

    func setPreferredMicrophone(identifier: String?, name: String?) {
        if let prefs = sharedSODictationPreferences() {
            let sel = NSSelectorFromString("setPreferredMicrophoneIdentifier:microphoneName:")
            if let imp = prefs.method(for: sel) {
                typealias SetMicFn = @convention(c) (AnyObject, Selector, NSString?, NSString?) -> Void
                let fn = unsafeBitCast(imp, to: SetMicFn.self)
                fn(prefs, sel, identifier as NSString?, name as NSString?)
            }
        } else {
            CFPreferencesSetAppValue("DictationIMMicrophoneIdentifier" as CFString, identifier as CFString?, speechPrefsDomain)
            CFPreferencesSetAppValue("DictationIMMicrophoneName" as CFString, name as CFString?, speechPrefsDomain)
            CFPreferencesAppSynchronize(speechPrefsDomain)
            DistributedNotificationCenter.default().postNotificationName(
                NSNotification.Name("DictationIMNotificationMicrophoneChanged"),
                object: nil,
                userInfo: nil,
                deliverImmediately: true
            )
        }
        onSettingsChanged?()
    }

    // MARK: - 4. Languages

    /// Returns all supported Dictation languages, with enabled state indicating which ones are active.
    func availableLanguages() -> [DictationLanguageOption] {
        CFPreferencesAppSynchronize(speechPrefsDomain)

        guard let prefCls = NSClassFromString("SODictationPreferences") as? NSObject.Type,
              let itemCls = NSClassFromString("SOSRLanguageItem") as? NSObject.Type else {
            return []
        }

        let visTableSel = NSSelectorFromString("visibleSRLanguageItemsTableUsingOffline:")
        var visTable: [String: Int] = [:]
        if let m = class_getClassMethod(itemCls, visTableSel) {
            typealias VisTableFn = @convention(c) (AnyClass, Selector, Bool) -> AnyObject?
            let fn = unsafeBitCast(method_getImplementation(m), to: VisTableFn.self)
            if let dict = fn(itemCls, visTableSel, false) as? [String: NSNumber] {
                for (k, v) in dict {
                    visTable[k] = v.intValue
                }
            }
        }

        // Also check activeNetworkBasedLanguageItems to ensure at least the best/active locales are marked enabled
        var activeLocales = Set<String>()
        for (loc, val) in visTable where val == 1 {
            activeLocales.insert(loc)
            activeLocales.insert(loc.replacingOccurrences(of: "-", with: "_"))
        }
        if let prefs = sharedSODictationPreferences() {
            let activeSel = NSSelectorFromString("activeNetworkBasedLanguageItems")
            if prefs.responds(to: activeSel),
               let activeItems = prefs.perform(activeSel)?.takeUnretainedValue() as? [NSObject] {
                for item in activeItems {
                    if let loc = item.value(forKey: "localeIdentifier") as? String {
                        activeLocales.insert(loc)
                        activeLocales.insert(loc.replacingOccurrences(of: "-", with: "_"))
                    }
                }
            }
        }

        let supportedSel = NSSelectorFromString("networkBasedDictationSupportedLanguages")
        guard let supported = prefCls.perform(supportedSel)?.takeUnretainedValue() as? NSArray else {
            return []
        }

        let itemsSel = NSSelectorFromString("languageItemsFromLocaleIdentifiers:usingOffline:")
        guard let itemsMethod = class_getClassMethod(itemCls, itemsSel) else {
            return []
        }
        typealias ItemsFn = @convention(c) (AnyClass, Selector, AnyObject, Bool) -> AnyObject?
        let itemsFn = unsafeBitCast(method_getImplementation(itemsMethod), to: ItemsFn.self)
        guard let languageItems = itemsFn(itemCls, itemsSel, supported, false) as? [NSObject] else {
            return []
        }

        // Count base languages so we show country/dialect whenever multiple locales share a base language
        var langCounts: [String: Int] = [:]
        for item in languageItems {
            let baseLang = item.value(forKey: "languageIdentifier") as? String ?? ""
            langCounts[baseLang, default: 0] += 1
        }

        var options: [DictationLanguageOption] = []
        var seenLocales = Set<String>()

        for item in languageItems {
            let baseLang = item.value(forKey: "languageIdentifier") as? String ?? ""
            if (langCounts[baseLang] ?? 0) > 1 {
                item.setValue(true, forKey: "showCountryInDisplayTitle")
            }
            guard let rawLoc = item.value(forKey: "localeIdentifier") as? String else { continue }
            let normLoc = rawLoc.replacingOccurrences(of: "-", with: "_")
            if seenLocales.contains(normLoc) { continue }
            seenLocales.insert(normLoc)

            let title = (item.value(forKey: "displayTitle") as? String)
                ?? Locale.current.localizedString(forIdentifier: normLoc)
                ?? normLoc
            let isEnabled = activeLocales.contains(rawLoc) || activeLocales.contains(normLoc)

            options.append(
                DictationLanguageOption(
                    localeIdentifier: normLoc,
                    displayTitle: title,
                    isEnabled: isEnabled
                )
            )
        }

        options.sort { $0.displayTitle.localizedStandardCompare($1.displayTitle) == .orderedAscending }
        return options
    }

    /// Toggles a dictation language on or off. Prevents disabling the last remaining enabled language.
    func toggleLanguage(_ localeIdentifier: String) {
        let all = availableLanguages()
        let enabledLocales = all.filter { $0.isEnabled }.map { $0.localeIdentifier }
        let normTarget = localeIdentifier.replacingOccurrences(of: "-", with: "_")
        let isCurrentlyEnabled = enabledLocales.contains(normTarget)

        // Do not allow disabling the last remaining active language
        if isCurrentlyEnabled && enabledLocales.count <= 1 {
            NSSound.beep()
            return
        }

        let newVisValue: UInt = isCurrentlyEnabled ? 0 : 1

        if let itemCls = NSClassFromString("SOSRLanguageItem") as? NSObject.Type {
            // Ensure all currently active items are explicitly represented in the visibility table first
            let visTableSel = NSSelectorFromString("visibleSRLanguageItemsTableUsingOffline:")
            let setVisSel = NSSelectorFromString("setVisibilityValue:forLocaleIdentifier:usingOffline:")
            if let setMethod = class_getClassMethod(itemCls, setVisSel) {
                typealias SetVisFn = @convention(c) (AnyClass, Selector, UInt, NSString, Bool) -> Void
                let setFn = unsafeBitCast(method_getImplementation(setMethod), to: SetVisFn.self)

                if let getMethod = class_getClassMethod(itemCls, visTableSel) {
                    typealias VisTableFn = @convention(c) (AnyClass, Selector, Bool) -> AnyObject?
                    let getFn = unsafeBitCast(method_getImplementation(getMethod), to: VisTableFn.self)
                    let existingDict = (getFn(itemCls, visTableSel, false) as? [String: NSNumber]) ?? [:]
                    for enabledLoc in enabledLocales where existingDict[enabledLoc] == nil {
                        setFn(itemCls, setVisSel, 1, enabledLoc as NSString, false)
                    }
                }

                setFn(itemCls, setVisSel, newVisValue, normTarget as NSString, false)
            }
        }

        // Update DictationIMPreferredLanguageIdentifiers & networkBasedLocaleIdentifier
        var updatedEnabled = enabledLocales
        if isCurrentlyEnabled {
            updatedEnabled.removeAll { $0 == normTarget }
        } else if !updatedEnabled.contains(normTarget) {
            updatedEnabled.append(normTarget)
        }

        if let prefs = sharedSODictationPreferences() {
            let setPrefLangsSel = NSSelectorFromString("setPreferredDictationLanguages:")
            if prefs.responds(to: setPrefLangsSel) {
                _ = prefs.perform(setPrefLangsSel, with: updatedEnabled as NSArray)
            }
            if !isCurrentlyEnabled {
                let setNetLocSel = NSSelectorFromString("setNetworkBasedLocaleIdentifier:")
                if prefs.responds(to: setNetLocSel) {
                    _ = prefs.perform(setNetLocSel, with: normTarget as NSString)
                }
            } else if let firstRemaining = updatedEnabled.first {
                let setNetLocSel = NSSelectorFromString("setNetworkBasedLocaleIdentifier:")
                if prefs.responds(to: setNetLocSel) {
                    _ = prefs.perform(setNetLocSel, with: firstRemaining as NSString)
                }
            }
        }

        CFPreferencesAppSynchronize(speechPrefsDomain)
        let dnc = DistributedNotificationCenter.default()
        dnc.postNotificationName(
            NSNotification.Name("DictationIMNotificationLanguageChanged"),
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
        dnc.postNotificationName(
            NSNotification.Name("com.apple.speech.DefaultSRLanguageChangedNotification"),
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )

        onSettingsChanged?()
    }

    // MARK: - 5. System Dictation Shortcut ("Shortcut" in System Settings)

    func currentSystemDictationShortcut() -> SystemDictationShortcutPreset {
        CFPreferencesAppSynchronize(speechPrefsDomain)
        CFPreferencesAppSynchronize("com.apple.symbolichotkeys" as CFString)

        guard let prefs = sharedSODictationPreferences() else {
            return .pressFnTwice
        }

        // Check if dictation hotkey is disabled
        let allowSel = NSSelectorFromString("allowEnablingViaHotKey")
        if let imp = prefs.method(for: allowSel) {
            typealias BoolFn = @convention(c) (AnyObject, Selector) -> Bool
            let fn = unsafeBitCast(imp, to: BoolFn.self)
            if !fn(prefs, allowSel) {
                return .off
            }
        }

        let hkSel = NSSelectorFromString("dictationHotKey")
        guard prefs.responds(to: hkSel),
              let hk = prefs.perform(hkSel)?.takeUnretainedValue() as? NSObject else {
            return .off
        }

        let isDoubleTap = (hk.value(forKey: "isDoubleTap") as? Bool) ?? false
        let modifiers = (hk.value(forKey: "modifiers") as? UInt) ?? 0
        let keyChar = (hk.value(forKey: "keyChar") as? UInt16) ?? 0
        let virtualKey = (hk.value(forKey: "virtualKey") as? UInt16) ?? 0

        if isDoubleTap {
            if (modifiers & 0x40000) != 0 {
                return .pressControlTwice
            } else if (modifiers & 0x10) != 0 {
                return .pressRightCommandTwice
            } else if (modifiers & 0x8) != 0 {
                return .pressLeftCommandTwice
            } else if (modifiers & 0x100000) != 0 {
                return .pressEitherCommandTwice
            } else if (modifiers & 0x800000) != 0 {
                return .pressFnTwice
            } else {
                return .off
            }
        } else {
            if virtualKey == 0xFFFF && keyChar == 0xFFFF {
                return .pressMicrophoneKey
            } else if virtualKey == 0 && keyChar == 0 && modifiers == 0 {
                return .off
            } else {
                let dispSel = NSSelectorFromString("displayString")
                let display = (hk.responds(to: dispSel) ? (hk.perform(dispSel)?.takeUnretainedValue() as? String) : nil) ?? "Custom"
                return .custom(keyChar: keyChar, virtualKey: virtualKey, modifiers: modifiers, displayString: display)
            }
        }
    }

    func mostRecentCustomSystemDictationShortcut() -> SystemDictationShortcutPreset? {
        guard let prefs = sharedSODictationPreferences() else { return nil }
        let sel = NSSelectorFromString("mostRecentCustomizedHotKey")
        guard prefs.responds(to: sel),
              let hk = prefs.perform(sel)?.takeUnretainedValue() as? NSObject else {
            return nil
        }
        let isDoubleTap = (hk.value(forKey: "isDoubleTap") as? Bool) ?? false
        let modifiers = (hk.value(forKey: "modifiers") as? UInt) ?? 0
        let keyChar = (hk.value(forKey: "keyChar") as? UInt16) ?? 0
        let virtualKey = (hk.value(forKey: "virtualKey") as? UInt16) ?? 0

        if !isDoubleTap && !(virtualKey == 0xFFFF && keyChar == 0xFFFF) && !(virtualKey == 0 && keyChar == 0 && modifiers == 0) {
            let dispSel = NSSelectorFromString("displayString")
            if let display = (hk.responds(to: dispSel) ? (hk.perform(dispSel)?.takeUnretainedValue() as? String) : nil),
               !display.isEmpty {
                return .custom(keyChar: keyChar, virtualKey: virtualKey, modifiers: modifiers, displayString: display)
            }
        }
        return nil
    }

    func setSystemDictationShortcut(_ preset: SystemDictationShortcutPreset) {
        guard let prefs = sharedSODictationPreferences(),
              let hkCls = NSClassFromString("SODictationHotKey") as? NSObject.Type else {
            return
        }

        if case .off = preset {
            let disableSel = NSSelectorFromString("disableDictationHotKey")
            if prefs.responds(to: disableSel) {
                _ = prefs.perform(disableSel)
            }
            let allowSel = NSSelectorFromString("setAllowEnablingViaHotKey:")
            if let imp = prefs.method(for: allowSel) {
                typealias SetBoolFn = @convention(c) (AnyObject, Selector, Bool) -> Void
                let fn = unsafeBitCast(imp, to: SetBoolFn.self)
                fn(prefs, allowSel, false)
            }
            DistributedNotificationCenter.default().postNotificationName(
                NSNotification.Name("IronwoodNotificationHotKeyChanged"),
                object: nil,
                userInfo: nil,
                deliverImmediately: true
            )
            onSettingsChanged?()
            return
        }

        let hk = hkCls.init()
        let setDoubleTapSel = NSSelectorFromString("setIsDoubleTap:")
        let setModifiersSel = NSSelectorFromString("setModifiers:")
        let setKeyCharSel = NSSelectorFromString("setKeyChar:")
        let setVirtualKeySel = NSSelectorFromString("setVirtualKey:")

        typealias SetBoolFn = @convention(c) (AnyObject, Selector, Bool) -> Void
        typealias SetUIntFn = @convention(c) (AnyObject, Selector, UInt) -> Void
        typealias SetUInt16Fn = @convention(c) (AnyObject, Selector, UInt16) -> Void

        let setDoubleTap = unsafeBitCast(hk.method(for: setDoubleTapSel)!, to: SetBoolFn.self)
        let setModifiers = unsafeBitCast(hk.method(for: setModifiersSel)!, to: SetUIntFn.self)
        let setKeyChar = unsafeBitCast(hk.method(for: setKeyCharSel)!, to: SetUInt16Fn.self)
        let setVirtualKey = unsafeBitCast(hk.method(for: setVirtualKeySel)!, to: SetUInt16Fn.self)

        switch preset {
        case .pressMicrophoneKey:
            setDoubleTap(hk, setDoubleTapSel, false)
            setKeyChar(hk, setKeyCharSel, 0xFFFF)
            setVirtualKey(hk, setVirtualKeySel, 0xFFFF)
            setModifiers(hk, setModifiersSel, 0)
        case .pressControlTwice:
            setDoubleTap(hk, setDoubleTapSel, true)
            setModifiers(hk, setModifiersSel, 0x40000)
        case .pressFnTwice:
            setDoubleTap(hk, setDoubleTapSel, true)
            setModifiers(hk, setModifiersSel, 0x800000)
        case .pressRightCommandTwice:
            setDoubleTap(hk, setDoubleTapSel, true)
            setModifiers(hk, setModifiersSel, 0x10)
        case .pressLeftCommandTwice:
            setDoubleTap(hk, setDoubleTapSel, true)
            setModifiers(hk, setModifiersSel, 0x8)
        case .pressEitherCommandTwice:
            setDoubleTap(hk, setDoubleTapSel, true)
            setModifiers(hk, setModifiersSel, 0x100000)
        case .custom(let keyChar, let virtualKey, let modifiers, _):
            setDoubleTap(hk, setDoubleTapSel, false)
            setKeyChar(hk, setKeyCharSel, keyChar)
            setVirtualKey(hk, setVirtualKeySel, virtualKey)
            setModifiers(hk, setModifiersSel, modifiers)
        case .off:
            break
        }

        let setHkSel = NSSelectorFromString("setDictationHotKey:")
        if prefs.responds(to: setHkSel) {
            _ = prefs.perform(setHkSel, with: hk)
        }
        onSettingsChanged?()
    }

    /// Opens macOS System Settings directly to the Keyboard > Dictation pane.
    func openDictationSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension?Dictation") {
            NSWorkspace.shared.open(url)
        } else if let fallbackURL = URL(string: "x-apple.systempreferences:com.apple.preference.keyboard?Dictation") {
            NSWorkspace.shared.open(fallbackURL)
        }
    }

    // MARK: - Private Helpers

    private func sharedSODictationPreferences() -> NSObject? {
        guard let cls = NSClassFromString("SODictationPreferences") as? NSObject.Type else { return nil }
        let sel = NSSelectorFromString("sharedDictationPreferences")
        guard cls.responds(to: sel) else { return nil }
        return cls.perform(sel)?.takeUnretainedValue() as? NSObject
    }

    private func postAssistantDarwinNotifications() {
        let darwinCenter = CFNotificationCenterGetDarwinNotifyCenter()
        CFNotificationCenterPostNotification(
            darwinCenter,
            CFNotificationName("AFDictationEnablementDidChangeDarwinNotification" as CFString),
            nil,
            nil,
            true
        )
        CFNotificationCenterPostNotification(
            darwinCenter,
            CFNotificationName("kAFPreferencesDidChangeDarwinNotification" as CFString),
            nil,
            nil,
            true
        )
    }

    private func findDictationInputSource() -> TISInputSource? {
        let properties = [
            kTISPropertyInputSourceID: dictationInputSourceID
        ] as CFDictionary

        guard let sourceList = TISCreateInputSourceList(properties, true)?.takeRetainedValue() as? [TISInputSource],
              let source = sourceList.first else {
            return nil
        }
        return source
    }

    private func querySystemDictationState() -> Bool {
        CFPreferencesAppSynchronize(assistantSupportDomain)
        var keyExistsAndHasValidFormat = DarwinBoolean(false)
        let assistantEnabled = CFPreferencesGetAppBooleanValue(
            assistantDictationKey,
            assistantSupportDomain,
            &keyExistsAndHasValidFormat
        )
        if keyExistsAndHasValidFormat.boolValue {
            return assistantEnabled
        }

        if let prefs = sharedSODictationPreferences() {
            let getSel = NSSelectorFromString("dictationEnabled")
            if let imp = prefs.method(for: getSel) {
                typealias GetFn = @convention(c) (AnyObject, Selector) -> Bool
                let getDictationEnabled = unsafeBitCast(imp, to: GetFn.self)
                return getDictationEnabled(prefs, getSel)
            }
        }

        if let inputSource = findDictationInputSource(),
           let enabledPtr = TISGetInputSourceProperty(inputSource, kTISPropertyInputSourceIsEnabled) {
            let cfBool = Unmanaged<CFBoolean>.fromOpaque(enabledPtr).takeUnretainedValue()
            return cfBool == kCFBooleanTrue
        }

        return false
    }

    private func setupNotifications() {
        let dnc = DistributedNotificationCenter.default()

        let notificationNames = [
            "DictationIMNotificationEnabledStateChanged",
            kTISNotifyEnabledKeyboardInputSourcesChanged as String,
            "AppleDictationPreferencesChangedNotification",
            "DictationIMNotificationMicrophoneChanged",
            "DictationIMNotificationLanguageChanged",
            "com.apple.speech.DefaultSRLanguageChangedNotification",
            "IronwoodNotificationHotKeyChanged"
        ]

        for name in notificationNames {
            dnc.addObserver(
                forName: NSNotification.Name(name),
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.refreshState()
                self?.onSettingsChanged?()
            }
        }

        let darwinCenter = CFNotificationCenterGetDarwinNotifyCenter()
        let observerPtr = Unmanaged.passUnretained(self).toOpaque()
        CFNotificationCenterAddObserver(
            darwinCenter,
            observerPtr,
            { (_, observer, _, _, _) in
                guard let observer = observer else { return }
                let controller = Unmanaged<DictationController>.fromOpaque(observer).takeUnretainedValue()
                DispatchQueue.main.async {
                    controller.refreshState()
                    controller.onSettingsChanged?()
                }
            },
            "AFDictationEnablementDidChangeDarwinNotification" as CFString,
            nil,
            .deliverImmediately
        )
    }
}

