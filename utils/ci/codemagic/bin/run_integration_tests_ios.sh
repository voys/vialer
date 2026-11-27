set -e # Ensures the script exits if any commands fail to execute

xcrun simctl shutdown all
latestRuntime="$(xcrun simctl list runtimes | grep -o -E 'iOS [0-9.]*' | sort -r | head -n1 | tr -d '[:space:]')"
testDevice=$(xcrun simctl create integration-test-simulator com.apple.CoreSimulator.SimDeviceType.iPhone-16-Pro "$latestRuntime")


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

# The Podfile deletes the pods' privacy manifests on CI, which breaks the
# simulator build because the pod targets still list them as resources.
export KEEP_POD_PRIVACY_MANIFESTS=true
./utils/bin/run-integration-tests --device="$testDevice" --suite=without-incoming-calls
