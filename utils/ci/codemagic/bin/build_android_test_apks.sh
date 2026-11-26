#!/bin/bash

# Builds the app APK and the instrumentation test APK that emulator.wtf uploads.
#
# The APKs are output to:
#   - build/app/outputs/apk/debug/app-debug.apk
#   - build/app/outputs/apk/androidTest/debug/app-debug-androidTest.apk

set -e

# emulator.wtf only runs x86_64 devices.
TARGET_PLATFORM="android-x64"

TARGET="integration_test/main_test.dart"
BRAND_FILE="brands/${BRAND:-vialer}.json"

# Both are set by run_emulator_wtf.sh when the suite includes incoming calls.
SUITE="${INTEGRATION_TEST_SUITE:-withoutIncomingCalls}"
BARESIP_HOST="${INTEGRATION_TEST_BARESIP_HOST:-127.0.0.1}"

DART_DEFINES=(
    "INTEGRATION_TEST_RUNNER=true"
    "INTEGRATION_TEST_SUITE=$SUITE"
    "INTEGRATION_TEST_BARESIP_HOST=$BARESIP_HOST"
)

# build.gradle reads the brand from the dart-defines Flutter hands to Gradle,
# so a direct Gradle build needs them too. Passing the exact same set also
# keeps Flutter's own build step a cache hit.
gradle_dart_defines() {
    {
        jq -r 'to_entries[] | "\(.key)=\(.value)"' "$BRAND_FILE"
        printf '%s\n' "${DART_DEFINES[@]}"
    } | while IFS= read -r define; do
        printf '%s' "$define" | base64 | tr -d '\n'
        echo
    done | paste -sd, -
}

echo "🔨 Building debug APK for $BRAND_FILE with integration test target ($SUITE suite)"
flutter build apk --debug \
    --target-platform="$TARGET_PLATFORM" \
    --target="$TARGET" \
    --dart-define-from-file="$BRAND_FILE" \
    "${DART_DEFINES[@]/#/--dart-define=}" > flutter_build_apk.log 2>&1 ||
    { tail -n 200 flutter_build_apk.log; exit 1; }

echo "🔧 Building Android instrumentation test APK"
GRADLE_DART_DEFINES="$(gradle_dart_defines)"
(cd android && ./gradlew app:assembleDebugAndroidTest \
    -Ptarget-platform="$TARGET_PLATFORM" \
    -Ptarget="$PWD/$TARGET" \
    -Pdart-defines="$GRADLE_DART_DEFINES")
