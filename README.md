# DictationMenu for macOS

A lightweight, native macOS menubar app (`LSUIElement`) that enables or disables **macOS System Dictation** (`System Settings > Keyboard > Dictation`) with a single click or a customizable global keyboard shortcut.

## Features

- **Menubar Status Icon**: Displays `mic.fill` when System Dictation is enabled and `mic.slash` when disabled.
- **One-Click System Dictation Toggle**: Enables or disables the macOS Dictation input source (`com.apple.inputmethod.ironwood`) and synchronizes `com.apple.hitoolbox` (`AppleDictationAutoEnable`).
- **Global Keyboard Shortcut**: Defaults to **Control + Option + Command + D (`⌃⌥⌘D`)** and works across all apps without needing Accessibility permissions.
- **Custom Shortcut Recorder**: Record any modifier + key combination via **Customize Shortcut…** in the menubar menu.
- **Real-Time Sync**: Automatically updates its menubar icon if Dictation is toggled externally in macOS System Settings.
- **Launch at Login**: Toggleable directly from the menu.

## Building & Running

Build the standalone `.app` bundle using the included build script:

```bash
./build.sh
```

This outputs the signed application bundle at `build/DictationMenu.app`.

### Launch the App

```bash
open build/DictationMenu.app
```

Optionally move it to `/Applications`:

```bash
cp -R build/DictationMenu.app /Applications/
open /Applications/DictationMenu.app
```
