set -e # Ensures the script exits if any commands fail to execute
if [ ! -f "build/ios/ipa/Vialer.ipa" ]; then
    echo "Error: You must run the build_ipa script before running iOS integration tests"
    exit 1
fi
# Required when running on Codemagic to fix some build issues.
export HOMEBREW_NO_INSTALL_CLEANUP=1
brew tap wix/brew && brew trust wix/brew && brew install applesimutils
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

# Returns 124 when the run hangs, otherwise the exit code of flutter drive.
run_with_watchdog() {
    flutter drive -t "$1" --driver test_driver/integration_test.dart -d "$testDevice" --dart-define-from-file="brands/$BRAND.json" &
    testPid=$!

    # Includes the Xcode build, which takes up to ~5 minutes on a cold cache.
    testDeadline=$((SECONDS + 900))
    while kill -0 "$testPid" 2>/dev/null; do
        if [ "$SECONDS" -ge "$testDeadline" ]; then
            echo "🚨 $1 did not finish within 15 minutes"
            kill "$testPid" 2>/dev/null || true
            wait "$testPid" 2>/dev/null || true
            xcrun simctl terminate "$testDevice" com.voipgrid.vialer 2>/dev/null || true
            return 124
        fi
        sleep 5
    done

    wait "$testPid"
}

# shellcheck disable=SC2044
for filename in $(find "integration_test/tests" -name "*.dart"); do
  flutter install --use-application-binary=build/ios/ipa/Vialer.ipa -d "$testDevice"
  applesimutils --booted --bundle com.voipgrid.vialer --setPermissions contacts=YES,microphone=YES,notifications=YES

  # The app launches fine when this happens, but flutter drive never picks up
  # the VM service URL, so a single retry is enough to get past it.
  status=0
  run_with_watchdog "$filename" || status=$?
  if [ "$status" -eq 124 ]; then
      echo "🔁 Retrying $filename once"
      run_with_watchdog "$filename"
  elif [ "$status" -ne 0 ]; then
      exit "$status"
  fi
done