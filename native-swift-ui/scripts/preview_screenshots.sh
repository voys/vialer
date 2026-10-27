#!/bin/sh
# Builds the Voys scheme for the simulator, launches it in UI preview mode on each main tab and
# saves a screenshot per tab. Debug builds only; see `AppContainer.isUIPreview`.
#
#   scripts/preview_screenshots.sh [output-dir] [simulator-udid]
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-$ROOT/.previews}"
SIM="${2:-$(xcrun simctl list devices available | grep -E "iPhone 17 Pro \(" | grep -oE '[0-9A-F-]{36}' | head -1)}"
mkdir -p "$OUT"
cd "$ROOT"

xcodebuild -project Vialer.xcodeproj -scheme Voys -configuration Debug-Voys \
    -destination "platform=iOS Simulator,id=$SIM" CODE_SIGNING_ALLOWED=NO -quiet build

APP="$(xcodebuild -project Vialer.xcodeproj -scheme Voys -configuration Debug-Voys \
    -destination "platform=iOS Simulator,id=$SIM" -showBuildSettings 2>/dev/null \
    | awk '/ TARGET_BUILD_DIR =/ { dir=$3 } / WRAPPER_NAME =/ { name=$3 } END { print dir "/" name }')"
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Info.plist")"

xcrun simctl boot "$SIM" 2>/dev/null || true
xcrun simctl install "$SIM" "$APP"
for tab in contacts recents settings dialer call; do
    xcrun simctl terminate "$SIM" "$BUNDLE_ID" 2>/dev/null || true
    xcrun simctl launch "$SIM" "$BUNDLE_ID" --ui-preview "--tab=$tab" >/dev/null
    sleep 3
    xcrun simctl io "$SIM" screenshot "$OUT/$tab.png" >/dev/null 2>&1
    echo "$OUT/$tab.png"
done
