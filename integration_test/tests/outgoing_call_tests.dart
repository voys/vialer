import 'package:vialer/data/models/call_records/call_record.dart';

import '../robots/calling_robot.dart';
import '../robots/dialer_robot.dart';
import '../utils/test_env.dart';
import '../utils/test_extensions.dart';
import '../utils/test_log.dart';
import 'verify_call_had_audio.dart';

Future<void> runOutgoingCallTests(IntegrationTestContext context) async {
  TestLog.group('📞', 'Outgoing calls');

  if (!context.config.canPlaceRealCalls) {
    const because =
        'this device cannot place a real call. They still run on Android CI '
        'and on a local simulator.';
    TestLog.skip('User can make a call', because: because);
    TestLog.skip('User can fill in the last dialled number', because: because);
    return;
  }

  await context.tester.navigateToContactsTab();

  final robot = CallingRobot(context.tester, context.config);

  final dialledAfter = DateTime.now().toUtc().subtract(
    const Duration(minutes: 1),
  );

  await TestLog.test('User can make a call', () => _userCanMakeACall(robot));
  await verifyCallHadAudio(
    context,
    direction: Direction.outbound,
    placedAfter: dialledAfter,
    thirdPartyNumber: TestEnv.integrationTestCallingPhoneNumber,
  );

  await TestLog.test(
    'User can fill in the last dialled number',
    () => _userCanFillInTheLastDialledNumber(context),
  );
}

Future<void> _userCanMakeACall(CallingRobot robot) async {
  final number = TestEnv.integrationTestCallingPhoneNumber;

  await robot.openDialer();
  TestLog.step('☎️', 'Dialling $number');
  await robot.enterPhoneNumber(number);
  await robot.tapCallButton();
  await robot.waitForCallToConnect();
  await robot.verifyCallDuration();
  TestLog.step('🔇', 'Muting and unmuting');
  await robot.toggleMuteOnAndOff();
  TestLog.step('⏸️', 'Putting the call on hold and resuming it');
  await robot.toggleHoldOnAndOff();
  TestLog.step('⏳', 'Staying in the call for 10s');
  await robot.waitFor(const Duration(seconds: 10));
  TestLog.step('🔴', 'Hanging up');
  await robot.tapHangUpButton();
  await robot.verifyCallScreenIsDismissed();
}

/// Only fills in the number, the call is never placed again.
Future<void> _userCanFillInTheLastDialledNumber(
  IntegrationTestContext context,
) async {
  final robot = DialerRobot(context.tester);

  await robot.openDialer();
  await robot.clearAnyPrefilledNumber();
  TestLog.detail(
    'Expected to be filled in',
    TestEnv.integrationTestCallingPhoneNumber,
  );
  await robot.tapCallButtonToFillInLastDialledNumber();
  robot.verifyEnteredNumber(TestEnv.integrationTestCallingPhoneNumber);

  await robot.deleteAllDigits();
  await robot.closeDialer();
}
