import 'package:flutter/foundation.dart';
import 'package:vialer/data/models/call_records/call_record.dart';

import '../robots/calling_robot.dart';
import '../utils/test_env.dart';
import '../utils/test_extensions.dart';
import 'verify_call_had_audio.dart';

Future<void> runOutgoingCallTests(IntegrationTestContext context) async {
  if (!context.config.canPlaceRealCalls) {
    debugPrint(
      'Skipping the outgoing call tests: this device cannot place a real '
      'call. They still run on Android CI and on a local simulator.',
    );
    return;
  }

  await context.tester.navigateToContactsTab();

  final robot = CallingRobot(context.tester, context.config);

  final dialledAfter = DateTime.now().toUtc().subtract(
    const Duration(minutes: 1),
  );

  await _userCanMakeACall(robot);
  await verifyCallHadAudio(
    context,
    direction: Direction.outbound,
    placedAfter: dialledAfter,
    thirdPartyNumber: TestEnv.integrationTestCallingPhoneNumber,
  );
}

Future<void> _userCanMakeACall(CallingRobot robot) async {
  await robot.openDialer();
  await robot.enterPhoneNumber(TestEnv.integrationTestCallingPhoneNumber);
  await robot.tapCallButton();
  await robot.waitForCallToConnect();
  await robot.verifyCallDuration();
  await robot.toggleMuteOnAndOff();
  await robot.toggleHoldOnAndOff();
  await robot.waitFor(const Duration(seconds: 10));
  await robot.tapHangUpButton();
  await robot.verifyCallScreenIsDismissed();
}
