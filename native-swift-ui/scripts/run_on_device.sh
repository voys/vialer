#!/bin/sh
# Builds a brand scheme, installs it on a connected iPhone and launches it with the console attached.
#
#   scripts/run_on_device.sh                 # Voys on the first connected iPhone
#   scripts/run_on_device.sh Vialer          # another brand scheme
#   DEVICE=<udid> scripts/run_on_device.sh   # a specific device (see `xcrun devicectl list devices`)
set -eu

SCHEME="${1:-Voys}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [ -z "${DEVICE:-}" ]; then
    DEVICE="$(xcrun devicectl list devices 2>/dev/null | grep physical | grep connected \
        | grep -oE '[0-9A-F]{8}-[0-9A-F]{16}' | head -1)"
fi
[ -n "$DEVICE" ] || { echo "No connected iPhone found; pass DEVICE=<udid>." >&2; exit 1; }

xcodebuild -project Vialer.xcodeproj -scheme "$SCHEME" -configuration "Debug-$SCHEME" \
    -destination "platform=iOS,id=$DEVICE" -allowProvisioningUpdates -quiet build

APP="$(xcodebuild -project Vialer.xcodeproj -scheme "$SCHEME" -configuration "Debug-$SCHEME" \
    -destination "platform=iOS,id=$DEVICE" -showBuildSettings 2>/dev/null \
    | awk '/ TARGET_BUILD_DIR =/ { dir=$3 } / WRAPPER_NAME =/ { name=$3 } END { print dir "/" name }')"
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Info.plist")"

xcrun devicectl device install app --device "$DEVICE" "$APP"
exec xcrun devicectl device process launch --console --terminate-existing --device "$DEVICE" "$BUNDLE_ID"
