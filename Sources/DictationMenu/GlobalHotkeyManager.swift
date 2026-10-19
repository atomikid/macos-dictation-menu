import Foundation
import Carbon
import AppKit

/// Represents a global keyboard shortcut with Carbon key code and modifiers.
struct KeyCombo: Codable, Equatable {
    var keyCode: UInt32
    var carbonModifiers: UInt32

    /// Default shortcut: Control + Option + Command + D (⌃⌥⌘D)
    static let defaultCombo = KeyCombo(
        keyCode: UInt32(kVK_ANSI_D),
        carbonModifiers: UInt32(controlKey | optionKey | cmdKey)
    )

    var nsEventModifierFlags: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if (carbonModifiers & UInt32(controlKey)) != 0 { flags.insert(.control) }
        if (carbonModifiers & UInt32(optionKey)) != 0 { flags.insert(.option) }
        if (carbonModifiers & UInt32(shiftKey)) != 0 { flags.insert(.shift) }
        if (carbonModifiers & UInt32(cmdKey)) != 0 { flags.insert(.command) }
        return flags
    }

    var keyEquivalentString: String {
        Self.keyCodeToString(keyCode).lowercased()
    }

    var displayString: String {
        var result = ""
        if (carbonModifiers & UInt32(controlKey)) != 0 { result += "⌃" }
        if (carbonModifiers & UInt32(optionKey)) != 0 { result += "⌥" }
        if (carbonModifiers & UInt32(shiftKey)) != 0 { result += "⇧" }
        if (carbonModifiers & UInt32(cmdKey)) != 0 { result += "⌘" }
        result += Self.keyCodeToString(keyCode)
        return result
    }

    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var mods: UInt32 = 0
        if flags.contains(.control) { mods |= UInt32(controlKey) }
        if flags.contains(.option) { mods |= UInt32(optionKey) }
        if flags.contains(.shift) { mods |= UInt32(shiftKey) }
        if flags.contains(.command) { mods |= UInt32(cmdKey) }
        return mods
    }

    static func keyCodeToString(_ keyCode: UInt32) -> String {
        switch Int(keyCode) {
        case kVK_ANSI_A: return "A"
        case kVK_ANSI_B: return "B"
        case kVK_ANSI_C: return "C"
        case kVK_ANSI_D: return "D"
        case kVK_ANSI_E: return "E"
        case kVK_ANSI_F: return "F"
        case kVK_ANSI_G: return "G"
        case kVK_ANSI_H: return "H"
        case kVK_ANSI_I: return "I"
        case kVK_ANSI_J: return "J"
        case kVK_ANSI_K: return "K"
        case kVK_ANSI_L: return "L"
        case kVK_ANSI_M: return "M"
        case kVK_ANSI_N: return "N"
        case kVK_ANSI_O: return "O"
        case kVK_ANSI_P: return "P"
        case kVK_ANSI_Q: return "Q"
        case kVK_ANSI_R: return "R"
        case kVK_ANSI_S: return "S"
        case kVK_ANSI_T: return "T"
        case kVK_ANSI_U: return "U"
        case kVK_ANSI_V: return "V"
        case kVK_ANSI_W: return "W"
        case kVK_ANSI_X: return "X"
        case kVK_ANSI_Y: return "Y"
        case kVK_ANSI_Z: return "Z"
        case kVK_ANSI_0: return "0"
        case kVK_ANSI_1: return "1"
        case kVK_ANSI_2: return "2"
        case kVK_ANSI_3: return "3"
        case kVK_ANSI_4: return "4"
        case kVK_ANSI_5: return "5"
        case kVK_ANSI_6: return "6"
        case kVK_ANSI_7: return "7"
        case kVK_ANSI_8: return "8"
        case kVK_ANSI_9: return "9"
        case kVK_Space: return "Space"
        case kVK_Return: return "↩"
        case kVK_Tab: return "⇥"
        case kVK_Delete: return "⌫"
        case kVK_ForwardDelete: return "⌦"
        case kVK_Escape: return "⎋"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        case kVK_F1: return "F1"
        case kVK_F2: return "F2"
        case kVK_F3: return "F3"
        case kVK_F4: return "F4"
        case kVK_F5: return "F5"
        case kVK_F6: return "F6"
        case kVK_F7: return "F7"
        case kVK_F8: return "F8"
        case kVK_F9: return "F9"
        case kVK_F10: return "F10"
        case kVK_F11: return "F11"
        case kVK_F12: return "F12"
        case kVK_ANSI_Minus: return "-"
        case kVK_ANSI_Equal: return "="
        case kVK_ANSI_LeftBracket: return "["
        case kVK_ANSI_RightBracket: return "]"
        case kVK_ANSI_Semicolon: return ";"
        case kVK_ANSI_Quote: return "'"
        case kVK_ANSI_Comma: return ","
        case kVK_ANSI_Period: return "."
        case kVK_ANSI_Slash: return "/"
        case kVK_ANSI_Backslash: return "\\"
        case kVK_ANSI_Grave: return "`"
        default: return "Key(\(keyCode))"
        }
    }
}

/// Manages registering and handling global hotkeys using the Carbon Event Manager API.
final class GlobalHotkeyManager: ObservableObject {
    static let shared = GlobalHotkeyManager()

    private let userDefaultsKey = "GlobalToggleDictationShortcut"
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?

    @Published var currentCombo: KeyCombo {
        didSet {
            saveCombo()
            registerHotKey()
            onShortcutChanged?(currentCombo)
        }
    }

    var onHotKeyPressed: (() -> Void)?
    var onShortcutChanged: ((KeyCombo) -> Void)?

    private init() {
        if let data = UserDefaults.standard.data(forKey: userDefaultsKey),
           let decoded = try? JSONDecoder().decode(KeyCombo.self, from: data) {
            self.currentCombo = decoded
        } else {
            self.currentCombo = .defaultCombo
        }
        installCarbonEventHandler()
        registerHotKey()
    }

    func resetToDefault() {
        currentCombo = .defaultCombo
    }

    private func saveCombo() {
        if let encoded = try? JSONEncoder().encode(currentCombo) {
            UserDefaults.standard.set(encoded, forKey: userDefaultsKey)
        }
    }

    private func installCarbonEventHandler() {
        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, event, userData) -> OSStatus in
                guard let userData = userData else { return OSStatus(eventNotHandledErr) }
                let manager = Unmanaged<GlobalHotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async {
                    manager.onHotKeyPressed?()
                }
                return noErr
            },
            1,
            &eventSpec,
            selfPtr,
            &eventHandlerRef
        )
    }

    func registerHotKey() {
        unregisterHotKey()

        let hotKeyID = EventHotKeyID(signature: OSType(0x44494354), id: 1) // 'DICT'
        let status = RegisterEventHotKey(
            currentCombo.keyCode,
            currentCombo.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        if status != noErr {
            NSLog("DictationMenu: Failed to register global hotkey (\(currentCombo.displayString)), status: \(status)")
        }
    }

    func unregisterHotKey() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
    }
}
