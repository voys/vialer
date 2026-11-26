import 'dart:io' show Platform;

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'tests/authentication_tests.dart';
import 'tests/cleanup_tests.dart';
import 'tests/contacts_tests.dart';
import 'tests/dialer_tests.dart';
import 'tests/incoming_call_tests.dart';
import 'tests/outgoing_call_tests.dart';
import 'tests/recents_tests.dart';
import 'tests/settings_tests.dart';
import 'utils/bootstrap.dart';
import 'utils/permission_mock.dart';
import 'utils/test_extensions.dart';
import 'utils/test_log.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Integration Tests', (WidgetTester tester) async {
    tester.ensureRunViaScript();
    mockPermissionsForIOS();

    final context = tester.asContext();
    final config = context.config;

    TestLog.start();
    TestLog.detail('Platform', Platform.operatingSystem);
    TestLog.detail('On an emulator or simulator', _isOnEmulator);
    TestLog.detail('On CI', _isCI);
    TestLog.detail('Suite', config.suite.name);
    TestLog.detail('Can place real calls', config.canPlaceRealCalls);
    TestLog.detail(
      'Checks call media is established',
      !config.skipTestingCallMediaEstablished,
    );

    await bootstrapAppForIntegrationTest();
    await tester.pumpAndSettle();

    await runAuthenticationTests(context);

    if (config.suite.everythingExceptIncomingCalls) {
      await runDialerTests(context);
      await runContactsTests(context);
      // Runs before the calls, and leaves the user available and ringing on
      // this device, which the call tests rely on.
      await runSettingsTests(context);
      await runOutgoingCallTests(context);
    }

    if (config.suite.includesIncomingCalls) {
      await runIncomingCallTests(context);
    }

    // Last, so the calls made above are in the history.
    if (config.suite.everythingExceptIncomingCalls) {
      await runRecentsTests(context);
    }

    await runCleanupTests(context);

    TestLog.finish();
  });
}

extension on WidgetTester {
  IntegrationTestContext asContext() => (
    tester: this,

    /// Configure the tests run based on the environment, any branching decisions
    /// that occur in tests based on environment should be defined in
    /// [TestConfiguration].
    config: (
      suite: _suite,
      // A CI machine has no audio input device, so the simulator booted there
      // cannot set up the audio channels a call needs: the app goes down the
      // moment the SIP stack starts the audio session, taking the whole run
      // with it. A simulator on a developer machine does get that far.
      canPlaceRealCalls: !(_isIOSSimulator && _isCI),
      // On the iOS simulator a call connects but media never establishes, so
      // the duration stays at its default rather than counting up. This is
      // known and documented by Apple; CallKit is only partially supported
      // there.
      skipTestingCallMediaEstablished: _isIOSSimulator,
    ),
  );
}

bool get _isCI => const bool.fromEnvironment('INTEGRATION_TEST_IS_CI');

bool get _isOnEmulator =>
    const bool.fromEnvironment('INTEGRATION_TEST_ON_EMULATOR');

bool get _isIOSSimulator => Platform.isIOS && _isOnEmulator;

/// Which tests this run covers. `./utils/bin/run-integration-tests` decides this
/// through its `--suite=` option and validates the value, so an unknown name
/// here means the define was passed by hand — [Iterable.byName] throwing is the
/// wanted outcome.
IntegrationTestSuite get _suite => IntegrationTestSuite.values.byName(
  const String.fromEnvironment(
    'INTEGRATION_TEST_SUITE',
    defaultValue: 'all',
  ),
);
