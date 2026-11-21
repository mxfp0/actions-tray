#!/bin/bash
# Builds a universal ActionsTray.app into build/.
# Usage: scripts/build-app.sh [--install]    (VERSION=1.2.0 sets the bundle version)
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${VERSION:-0.0.0}"
ARCHS=(--arch arm64 --arch x86_64)
# SwiftPM links through `clang --sysroot`, which records the deployment target as the SDK version.
# That puts SwiftUI in compatibility mode, where the MenuBarExtra window never shrinks.
SDK_FLAGS=(-Xswiftc -Xclang-linker -Xswiftc -isysroot -Xswiftc -Xclang-linker -Xswiftc "$(xcrun --show-sdk-path)")

swift build -c release "${ARCHS[@]}" "${SDK_FLAGS[@]}"
BIN="$(swift build -c release "${ARCHS[@]}" --show-bin-path)/ActionsTray"
APP=build/ActionsTray.app

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/ActionsTray"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"

if [[ "${1:-}" == "--install" ]]; then
    pkill -x ActionsTray || true
    rm -rf /Applications/ActionsTray.app
    cp -R "$APP" /Applications/
    open /Applications/ActionsTray.app
    echo "Installed /Applications/ActionsTray.app"
else
    echo "Built $APP ($VERSION)"
fi
