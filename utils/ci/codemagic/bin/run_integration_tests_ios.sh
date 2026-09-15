set -e # Ensures the script exits if any commands fail to execute
if [ ! -f "build/ios/ipa/Vialer.ipa" ]; then
    echo "Error: You must run the build_ipa script before running iOS integration tests"
    exit 1
fi
xcrun simctl shutdown all
latestRuntime="$(xcrun simctl list runtimes | grep -o -E 'iOS [0-9.]*' | sort -r | head -n1 | tr -d '[:space:]')"
testDevice=$(xcrun simctl create integration-test-simulator com.apple.CoreSimulator.SimDeviceType.iPhone-14-Pro "$latestRuntime")
xcrun simctl bootstatus "$testDevice" -b &
bootStatusPid=$!

bootDeadline=$((SECONDS + 300))
while kill -0 "$bootStatusPid" 2>/dev/null; do
    if [ "$SECONDS" -ge "$bootDeadline" ]; then
        echo "🚨 Simulator $testDevice did not finish booting within 5 minutes"
        kill -9 "$bootStatusPid" 2>/dev/null || true
        exit 1
    fi
    sleep 5
done

if ! wait "$bootStatusPid"; then
    echo "🚨 Simulator $testDevice failed to boot"
    exit 1
fi

# shellcheck disable=SC2044
for filename in $(find "integration_test/tests" -name "*.dart"); do
  flutter drive -t "$filename" --driver test_driver/integration_test.dart -d "$testDevice" --dart-define-from-file="brands/$BRAND.json"
done