#!/bin/bash

# Runs the Android integration tests on emulator.wtf.
#
# By default this runs on the merge request devices; pass --nightly for the
# wider set the scheduled nightly run covers.
#
# --suite=<suite> picks the tests, without-incoming-calls by default. A suite
# with incoming calls needs baresip already running on this machine.

set -e

# Run `ew-cli --models` for the available models and API levels.
MERGE_REQUEST_DEVICES=(
    "model=Pixel7,version=35"
)
NIGHTLY_DEVICES=(
    # Newest model and API level emulator.wtf offers.
    "model=Pixel7,version=37"
    # Oldest API level the app supports, keep in sync with minSdkVersion.
    "model=Pixel2,version=26"
)

# Where the emulator finds this machine's localhost, and with it baresip. Has to
# be a private address that nothing the tests talk to lives on.
BARESIP_HOST="192.168.200.1"

RUN_NAME="merge-request"
DEVICES=("${MERGE_REQUEST_DEVICES[@]}")
SUITE="without-incoming-calls"
for arg in "$@"; do
    case "$arg" in
        --nightly)
            RUN_NAME="nightly"
            DEVICES=("${NIGHTLY_DEVICES[@]}")
            ;;
        --suite=*) SUITE="${arg#--suite=}" ;;
        *)
            echo "🚨 Unknown option: $arg"
            echo "   Supported: --nightly | --suite=<suite>"
            exit 1
            ;;
    esac
done

# Keep in sync with IntegrationTestSuite in integration_test/utils/test_extensions.dart.
INCOMING_CALL_ARGS=()
case "$SUITE" in
    without-incoming-calls)
        export INTEGRATION_TEST_SUITE="withoutIncomingCalls"
        ;;
    incoming-calls|all)
        [ "$SUITE" = "all" ] && export INTEGRATION_TEST_SUITE="all" || export INTEGRATION_TEST_SUITE="incomingCalls"
        export INTEGRATION_TEST_BARESIP_HOST="$BARESIP_HOST"
        # The tunnel sends all of the emulator's traffic through this machine,
        # which is what lets it reach baresip here.
        INCOMING_CALL_ARGS=(--egress-tunnel --egress-localhost-fwd-ip "$BARESIP_HOST" --environment-variables refreshPushConnection=true)
        ;;
    *)
        echo "🚨 Unknown suite: $SUITE"
        echo "   Supported: --suite=all | --suite=incoming-calls | --suite=without-incoming-calls"
        exit 1
        ;;
esac

if [[ -z "${EW_TOKEN:-}" && -f .secrets/emulator-wtf-token ]]; then
    EW_TOKEN=$(cat .secrets/emulator-wtf-token)
fi

if [ -z "${EW_TOKEN:-}" ]; then
    echo "🚨 EW_TOKEN is not set"
    echo "🚨 Grab the emulator.wtf developer token from Keyhub."
    echo "🚨 Then store it locally so future runs pick it up automatically:"
    echo "   $ mkdir -p .secrets && echo \"<token>\" > .secrets/emulator-wtf-token"
    echo "🚨 On Codemagic this is provided by the 'integration_testing' environment group."
    exit 1
fi

EW_CLI="ew-cli"
if ! command -v ew-cli &> /dev/null; then
    EW_CLI="$HOME/bin/ew-cli"
    if [ ! -x "$EW_CLI" ]; then
        echo "📦 Installing emulator.wtf CLI to $EW_CLI"
        mkdir -p "$HOME/bin"
        curl -fsSL https://maven.emulator.wtf/releases/ew-cli -o "$EW_CLI"
        chmod a+x "$EW_CLI"
    fi
fi

./utils/ci/codemagic/bin/build_android_test_apks.sh

rm -rf emulator_wtf_results

FAILED_DEVICES=()
RESULTS_LINKS_FILE=$(mktemp)

# Passes ew-cli's output through and calls out the run's results page as soon
# as ew-cli prints it, which is long before the run ends. The link is kept for
# print_results_links, which repeats it at the end of the log.
highlight_results_link() {
    DEVICE="$1" RESULTS_LINKS_FILE="$RESULTS_LINKS_FILE" perl -pe '
        BEGIN { $| = 1; open($links, ">>", $ENV{RESULTS_LINKS_FILE}) or die "$!"; $links->autoflush(1) }
        if (!$seen && m{(https://[\w.-]*emulator\.wtf/[^\s\x1b\x07"<>]+)}) {
            my $url = $1;
            if ($url !~ m{//(?:docs|maven|api|files)\.emulator\.wtf}) {
                $seen = 1;
                print $links "   • $ENV{DEVICE}: $url\n";
                $_ .= "🔗 emulator.wtf results: $url\n";
            }
        }'
}

print_results_links() {
    if [ -s "$RESULTS_LINKS_FILE" ]; then
        echo "🔗 emulator.wtf results:"
        cat "$RESULTS_LINKS_FILE"
    else
        echo "⚠️  ew-cli printed no emulator.wtf results link"
    fi
}

# Devices run sequentially to avoid race conditions: the integration tests share a single
# account, so a call placed during one run could ring the other.
# For the same reason there is only one flaky retry, as emulator.wtf starts additional
# attempts in parallel. The tests talk to the live backend, so a cached result from an
# earlier run with the same APKs proves nothing; hence --no-test-cache. No --side-effects:
# the tests clean up after themselves, and that flag stops emulator.wtf from retrying its
# own infrastructure errors, such as a failing adb call before any test ran.
for i in "${!DEVICES[@]}"; do
    device="${DEVICES[$i]}"

    echo "🧪 Running Android integration tests on emulator.wtf ($((i + 1))/${#DEVICES[@]}): $device"
    "$EW_CLI" \
        --token "$EW_TOKEN" \
        --app "build/app/outputs/apk/debug/app-debug.apk" \
        --test "build/app/outputs/apk/androidTest/debug/app-debug-androidTest.apk" \
        --device "$device" \
        --display-name "$RUN_NAME $SUITE $device" \
        "${INCOMING_CALL_ARGS[@]}" \
        --no-test-cache \
        --num-flaky-test-attempts 1 \
        --timeout 15m \
        --record-video \
        --outputs merged_results_xml,coverage,pulled_dirs,logcat,captured_video \
        --outputs-dir "emulator_wtf_results/$i" 2>&1 | highlight_results_link "$device"
    if [ "${PIPESTATUS[0]}" -ne 0 ]; then
        FAILED_DEVICES+=("$device")
    fi
done

if [ "${#FAILED_DEVICES[@]}" -gt 0 ]; then
    # Codemagic only publishes artifacts for a successful build, so a failure
    # has to print what is needed to debug it.
    if [ "${#INCOMING_CALL_ARGS[@]}" -gt 0 ]; then
        echo "🚨 Test results:"
        find emulator_wtf_results -name "*.xml" -exec cat {} + || true
        echo "🚨 Last 100 lines of the baresip log:"
        tail -n 100 ~/.baresip/baresip.log || true
    fi

    echo "❌ emulator.wtf integration tests FAILED on:"
    for device in "${FAILED_DEVICES[@]}"; do
        echo "   • $device"
    done
    print_results_links
    exit 1
fi

echo "🎉 All emulator.wtf integration tests PASSED on ${#DEVICES[@]} device(s)! 🎉"
print_results_links
