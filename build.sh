#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
app_path="${1:-$PWD/build/DualSense Codex.app}"
mkdir -p "$app_path/Contents/MacOS" "$PWD/build/module-cache"
xcrun swiftc -target "$(uname -m)-apple-macosx12.0" -swift-version 5 -O -module-cache-path "$PWD/build/module-cache" \
  -framework AppKit -framework ApplicationServices -framework GameController -framework CoreHaptics \
  Sources/HoldState.swift Sources/TriggerGesture.swift Sources/StickNavigation.swift Sources/ConversationGeometry.swift Sources/ConversationLocator.swift Sources/main.swift -o "$app_path/Contents/MacOS/DualSenseCodex"
xcrun swiftc -target "$(uname -m)-apple-macosx12.0" -swift-version 5 -O -module-cache-path "$PWD/build/module-cache" \
  Sources/notify-hook.swift -o "$app_path/Contents/MacOS/DualSenseNotify"
codesign --force --sign - "$app_path/Contents/MacOS/DualSenseNotify"
cp Info.plist "$app_path/Contents/Info.plist"
# File Provider / Finder may add this attribute to generated app bundles.
# codesign rejects it, so remove it only from our own build output.
xattr -dr com.apple.FinderInfo "$app_path" 2>/dev/null || true
codesign --force --sign - "$app_path"
printf 'Built: %s\n' "$app_path"
