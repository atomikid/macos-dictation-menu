import Foundation
import Carbon
import AppKit
import Darwin

/// Manages reading and toggling the macOS System Dictation setting across:
/// - `com.apple.assistant.support` (`"Dictation Enabled"`) — the backing store for `AFPreferences` and `SODictationPreferences` in macOS System Settings
/// - Carbon Text Input Source (`com.apple.inputmethod.ironwood`)
/// - `com.apple.hitoolbox` (`"AppleDictationAutoEnable"`)
/// - `com.apple.speech.recognition.AppleSpeechRecognition.prefs` (`"DictationIMMasterDictationEnabled"`)
final class DictationController: ObservableObject {
    static let shared = DictationController()

    private let dictationInputSourceID = "com.apple.inputmethod.ironwood"
    private let assistantSupportDomain = "com.apple.assistant.support" as CFString
    private let assistantDictationKey = "Dictation Enabled" as CFString

    private let hitoolboxDomain = "com.apple.hitoolbox" as CFString
    private let autoEnableKey = "AppleDictationAutoEnable" as CFString

    private let speechPrefsDomain = "com.apple.speech.recognition.AppleSpeechRecognition.prefs" as CFString
    private let masterEnabledKey = "DictationIMMasterDictationEnabled" as CFString
    private let introPresentedKey = "DictationIMIntroMessagePresented" as CFString
    private let allowHotKeyKey = "DictationIMAllowEnablingViaHotKey" as CFString

    private var darwinNotifyToken: Int32 = 0

    @Published private(set) var isDictationEnabled: Bool = false

    var onStateChanged: ((Bool) -> Void)?

    private init() {
        // Load SpeechObjects & DictationServices if available for live verification
        dlopen("/System/Library/PrivateFrameworks/SpeechObjects.framework/SpeechObjects", RTLD_LAZY)
        dlopen("/System/Library/PrivateFrameworks/SpeechObjects.framework/Versions/A/Frameworks/DictationServices.framework/DictationServices", RTLD_LAZY)

        refreshState()
        setupNotifications()
    }

    deinit {
        let darwinCenter = CFNotificationCenterGetDarwinNotifyCenter()
        CFNotificationCenterRemoveEveryObserver(darwinCenter, Unmanaged.passUnretained(self).toOpaque())
    }

    /// Queries the current system Dictation state from `com.apple.assistant.support` / `SODictationPreferences`.
    @discardableResult
    func refreshState() -> Bool {
        let current = querySystemDictationState()
        if isDictationEnabled != current {
            isDictationEnabled = current
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

        // 1. Update com.apple.assistant.support -> "Dictation Enabled" (primary macOS System Settings backing key)
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
        // 1. Check com.apple.assistant.support -> "Dictation Enabled" (authoritative store used by AFPreferences & System Settings)
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

        // 2. Fallback to SODictationPreferences.sharedDictationPreferences().dictationEnabled() if loaded
        if let cls = NSClassFromString("SODictationPreferences") as? NSObject.Type {
            let sharedSel = NSSelectorFromString("sharedDictationPreferences")
            let getSel = NSSelectorFromString("dictationEnabled")
            if let prefs = cls.perform(sharedSel)?.takeUnretainedValue() as? NSObject,
               let imp = prefs.method(for: getSel) {
                typealias GetFn = @convention(c) (AnyObject, Selector) -> Bool
                let getDictationEnabled = unsafeBitCast(imp, to: GetFn.self)
                return getDictationEnabled(prefs, getSel)
            }
        }

        // 3. Fallback to Carbon TIS input source property
        if let inputSource = findDictationInputSource(),
           let enabledPtr = TISGetInputSourceProperty(inputSource, kTISPropertyInputSourceIsEnabled) {
            let cfBool = Unmanaged<CFBoolean>.fromOpaque(enabledPtr).takeUnretainedValue()
            return cfBool == kCFBooleanTrue
        }

        return false
    }

    private func setupNotifications() {
        let dnc = DistributedNotificationCenter.default()

        // Observe DictationIMNotificationEnabledStateChanged (posted when System Settings toggles Dictation)
        dnc.addObserver(
            forName: NSNotification.Name("DictationIMNotificationEnabledStateChanged"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshState()
        }

        dnc.addObserver(
            forName: NSNotification.Name(kTISNotifyEnabledKeyboardInputSourcesChanged as String),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshState()
        }

        dnc.addObserver(
            forName: NSNotification.Name("AppleDictationPreferencesChangedNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshState()
        }

        // Also observe Darwin notification AFDictationEnablementDidChangeDarwinNotification
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
                }
            },
            "AFDictationEnablementDidChangeDarwinNotification" as CFString,
            nil,
            .deliverImmediately
        )
    }
}
