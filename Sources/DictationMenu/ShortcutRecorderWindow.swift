import SwiftUI
import AppKit
import Carbon

/// Manages the floating window for customizing the global keyboard shortcut.
final class ShortcutRecorderWindowController: NSWindowController, NSWindowDelegate {
    static let shared = ShortcutRecorderWindowController()

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 220),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Customize Dictation Shortcut"
        window.center()
        window.isReleasedWhenClosed = false
        window.level = .floating
        super.init(window: window)
        window.delegate = self
        window.contentView = NSHostingView(rootView: ShortcutRecorderView(onClose: { [weak self] in
            self?.close()
        }))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func showRecorder() {
        guard let window = window else { return }
        NSApp.activate(ignoringOtherApps: true)
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        GlobalHotkeyManager.shared.registerHotKey()
    }
}

struct ShortcutRecorderView: View {
    @ObservedObject var hotkeyManager = GlobalHotkeyManager.shared
    @State private var isRecording = false
    @State private var statusMessage: String = "Click 'Record New Shortcut' and press your desired key combination."
    @State private var eventMonitor: Any?

    var onClose: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "keyboard")
                    .font(.system(size: 24))
                    .foregroundColor(.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Global Dictation Shortcut")
                        .font(.headline)
                    Text("Toggles macOS System Dictation from anywhere.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }

            // Shortcut Badge Box
            HStack {
                Spacer()
                Text(isRecording ? "Press keys now…" : hotkeyManager.currentCombo.displayString)
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundColor(isRecording ? .accentColor : .primary)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 24)
                Spacer()
            }
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(NSColor.controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(isRecording ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: isRecording ? 2 : 1)
                    )
            )
            .onTapGesture {
                toggleRecording()
            }

            Text(statusMessage)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(height: 28)

            HStack(spacing: 12) {
                Button(action: {
                    stopRecording()
                    hotkeyManager.resetToDefault()
                    statusMessage = "Reset to default shortcut (⌃⌥⌘D)."
                }) {
                    Text("Reset to Default (⌃⌥⌘D)")
                }

                Spacer()

                Button(action: {
                    toggleRecording()
                }) {
                    Text(isRecording ? "Cancel" : "Record New Shortcut")
                }
                .keyboardShortcut(.defaultAction)

                Button("Done") {
                    stopRecording()
                    onClose()
                }
            }
        }
        .padding(20)
        .frame(width: 380, height: 220)
        .onDisappear {
            stopRecording()
        }
    }

    private func toggleRecording() {
        if isRecording {
            stopRecording()
            statusMessage = "Recording cancelled."
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        isRecording = true
        statusMessage = "Press a modifier key (⌘, ⌥, ⌃, or ⇧) + any key. Press Esc to cancel."
        hotkeyManager.unregisterHotKey()

        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let keyCode = UInt32(event.keyCode)

            // Esc cancels recording
            if Int(keyCode) == kVK_Escape {
                stopRecording()
                statusMessage = "Recording cancelled."
                return nil
            }

            let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
            let isFunctionKey = (Int(keyCode) >= kVK_F1 && Int(keyCode) <= kVK_F12)

            guard !flags.isEmpty || isFunctionKey else {
                statusMessage = "Please include at least one modifier key (⌘, ⌥, ⌃, or ⇧)."
                NSSound.beep()
                return nil
            }

            let carbonMods = KeyCombo.carbonModifiers(from: flags)
            let newCombo = KeyCombo(keyCode: keyCode, carbonModifiers: carbonMods)
            hotkeyManager.currentCombo = newCombo
            isRecording = false
            removeMonitor()
            statusMessage = "Saved new shortcut: \(newCombo.displayString)"
            return nil
        }
    }

    private func stopRecording() {
        if isRecording {
            isRecording = false
            removeMonitor()
            hotkeyManager.registerHotKey()
        }
    }

    private func removeMonitor() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }
}
