<p align="center">
  <img src="Resources/AppIcon.png" width="128" height="128" alt="DictationMenu Icon">
</p>

<h1 align="center">DictationMenu for macOS</h1>

<p align="center">
  A lightweight, native macOS menubar app that lets you view, configure, and toggle <strong>macOS System Dictation</strong> (<code>System Settings &gt; Keyboard &gt; Dictation</code>) with a single click or a customizable global keyboard shortcut.
</p>

<p align="center">
  <a href="https://github.com/atomikid/macos-dictation-menu/raw/main/Distribution/MacOS%20Dictation%20menu.dmg">
    <img src="https://img.shields.io/badge/Direct%20Download-.dmg-blue?style=for-the-badge&logo=apple" alt="Direct Download .dmg">
  </a>
</p>

---

## 📥 Direct Download

You can download the latest pre-built application directly:

👉 **[Direct Download: MacOS Dictation menu.dmg](https://github.com/atomikid/macos-dictation-menu/raw/main/Distribution/MacOS%20Dictation%20menu.dmg)**

1. Open the downloaded `MacOS Dictation menu.dmg` file (double-click to mount it).
2. Drag `DictationMenu.app` into your `/Applications` folder.
3. Open `DictationMenu.app` from `/Applications` (or Spotlight / Raycast).

### 🛡️ First Launch & macOS Security (Unknown Developer)

Since the app is built and distributed directly outside the Mac App Store, macOS may block it on first launch with a warning that the developer cannot be verified or is unknown.

To allow `DictationMenu.app` to run:

1. Open **System Settings** on your Mac.
2. Navigate to **Privacy & Security** and scroll down to the **Security** section.
3. Under Security, locate the message: *“DictationMenu.app” was blocked to protect your Mac.*
4. Click the **Open Anyway** button next to it.
5. In the confirmation dialog, click **Open** (and provide your Mac password or Touch ID if requested).

<p align="center">
  <img src="Resources/macos-security-open-anyway.png" width="600" alt="macOS Security - Open Anyway in System Settings">
</p>

> **Note:** This is only required once. Afterwards, DictationMenu will open directly without warnings.

---

## 📸 Screenshots

<p align="center">
  <img src="Resources/dictation-menu-on.png" width="48%" alt="DictationMenu Open - Dictation On">
  &nbsp;
  <img src="Resources/dictation-menu-off.png" width="48%" alt="DictationMenu Open - Dictation Off">
</p>

<p align="center">
  <em>Left: Menubar menu when System Dictation is enabled (<code>mic.fill</code>). Right: Menubar menu when System Dictation is disabled (<code>mic.slash</code>).</em>
</p>

---

## 💻 System Requirements

| Requirement | Specification |
| :--- | :--- |
| **Operating System** | macOS 13.0 (Ventura) or later (macOS 13 Ventura, macOS 14 Sonoma, macOS 15 Sequoia, and newer) |
| **Architecture** | Apple Silicon (M1 / M2 / M3 / M4) and Intel Macs |
| **Dictation** | macOS System Dictation supported (`System Settings > Keyboard > Dictation`) |
| **Permissions** | **No Accessibility permissions needed!** Global hotkeys work system-wide without special security entitlements |

---

## ✨ Features

- **Menubar Status Icon**: Dynamic status indicator in your menu bar — displays `mic.fill` when macOS System Dictation is active and `mic.slash` when disabled.
- **One-Click Toggle**: Enable or disable macOS System Dictation instantly from the menu bar without opening System Settings.
- **Global Keyboard Shortcut**: Defaults to **Control + Option + Command + D (`⌃⌥⌘D`)** to toggle Dictation on and off anywhere, inside any application.
- **Custom Shortcut Recorder**: Record any modifier + key combination via **Toggle On/Off Hotkey…** to suit your personal keyboard preferences.
- **Complete System Dictation Controls**:
  - 🌐 **Languages**: Quick-switch active dictation languages and enable additional installed locales.
  - 🎙️ **Microphone Source**: Select input microphone directly (Automatic, built-in, AirPods, USB audio interfaces, or external mics).
  - ⌨️ **System Dictation Shortcut**: Configure the native macOS dictation invocation key (e.g., Press 🎤 Dictation Key, Press Control Key Twice, Press Fn Twice, Press Command Twice, Custom, or Off).
  - ✍️ **Auto-Punctuation**: Toggle macOS automatic punctuation on or off with a single click.
- **Real-Time Sync**: Automatically reflects the menubar icon and menu state if Dictation is changed outside the app in macOS System Settings.
- **Launch at Login**: Enable or disable launch on system startup directly from the menu.

---

## 🛠️ Building & Running from Source

If you prefer to compile the application bundle yourself:

### 1. Clone the Repository

```bash
git clone https://github.com/atomikid/macos-dictation-menu.git
cd macos-dictation-menu
```

### 2. Build the Application Bundle

Run the provided build script:

```bash
./build.sh
```

This compiles all Swift sources, packages the application icon (`AppIcon.icns`), generates the `Info.plist`, and outputs a signed bundle at `build/DictationMenu.app`.

### 3. Launch or Install

Run the freshly compiled app:

```bash
open build/DictationMenu.app
```

Or install it to `/Applications`:

```bash
cp -R build/DictationMenu.app /Applications/
open /Applications/DictationMenu.app
```

---

## 📄 License

This project is licensed under the MIT License.

