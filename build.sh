#!/usr/bin/env bash
set -euo pipefail

APP_NAME="DictationMenu"
BUNDLE_ID="com.joaoferreira.dictationmenu"
BUILD_DIR="build"
APP_BUNDLE="${BUILD_DIR}/${APP_NAME}.app"
CONTENTS_DIR="${APP_BUNDLE}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
MODULE_CACHE="/tmp/dictationmenu-swift-cache"

echo "🔨 Compiling ${APP_NAME}..."
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}" "${MODULE_CACHE}"

DEVELOPER_DIR=/Library/Developer/CommandLineTools \
/Library/Developer/CommandLineTools/usr/bin/swiftc \
    -O \
    -parse-as-library \
    -module-cache-path "${MODULE_CACHE}" \
    -sdk /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk \
    -target arm64-apple-macosx13.0 \
    -framework AppKit \
    -framework SwiftUI \
    -framework Carbon \
    -framework ServiceManagement \
    Sources/DictationMenu/DictationController.swift \
    Sources/DictationMenu/GlobalHotkeyManager.swift \
    Sources/DictationMenu/ShortcutRecorderWindow.swift \
    Sources/DictationMenu/main.swift \
    -o "${MACOS_DIR}/${APP_NAME}"

if [ -f "Resources/AppIcon.icns" ]; then
    cp "Resources/AppIcon.icns" "${RESOURCES_DIR}/AppIcon.icns"
fi

cat > "${CONTENTS_DIR}/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>Dictation Menu</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

# Ad-hoc code sign the bundle so macOS allows running & hotkey registration cleanly
codesign --force --deep --sign - "${APP_BUNDLE}"

echo "✅ Built app bundle at: ${APP_BUNDLE}"
