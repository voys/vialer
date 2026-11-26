import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vialer/data/models/call_records/call_record.dart';
import 'package:vialer/data/repositories/call_records/personal/recent_call_repository.dart';
import 'package:vialer/dependency_locator.dart';

import '../robots/calling_robot.dart';
import '../utils/baresip_client.dart';
import '../utils/test_env.dart';
import '../utils/test_extensions.dart';
import 'verify_call_had_audio.dart';

Future<void> runIncomingCallTests(IntegrationTestContext context) async {
  await context.tester.navigateToContactsTab();

  final robot = CallingRobot(context.tester, context.config);

  final receivedAfter = DateTime.now().toUtc().subtract(
    const Duration(minutes: 1),
  );

  await _userCanReceiveACall(context.tester, robot);
  await verifyCallHadAudio(
    context,
    direction: Direction.inbound,
    placedAfter: receivedAfter,
  );

  await _userCanTransferACall(robot);
  await _userCanDeclineACall(context.tester, robot);
  await _unansweredCallIsMissed(context.tester, robot);
}

/// Digits that are easy to tell apart in baresip's log.
const _dtmfDigits = '1590';

Future<void> _userCanReceiveACall(
  WidgetTester tester,
  CallingRobot robot,
) async {
  final baresip = await BaresipClient.connect();

  try {
    // Wait so the user is registered properly before making a call
    debugPrint('Connected to baresip, going to make a call in 5s.');
    await robot.waitFor(const Duration(seconds: 5));
    await baresip.dial(TestEnv.integrationTestIncomingCallNumber);

    await robot.waitForIncomingCallToRing();
    robot.verifyCallIsIncoming();
    await robot.ringFor(const Duration(seconds: 3));
    await robot.answerIncomingCall();
    await robot.waitForAnsweredCallToConnect();
    await robot.verifyCallDuration();

    await robot.sendDtmf(_dtmfDigits);
    await tester.pumpUntil(
      () => baresip.receivedDtmf.contains(_dtmfDigits),
      reason:
          'baresip should receive the DTMF digits $_dtmfDigits sent through '
          'the in-call keypad, it received "${baresip.receivedDtmf}"',
      settle: false,
    );

    await robot.toggleSpeakerOnAndOff();
    await robot.waitFor(const Duration(seconds: 5));
    await robot.tapHangUpButton();
    await robot.verifyCallScreenIsDismissed();
  } finally {
    await baresip.hangup();
    await baresip.close();
  }
}

/// Transfers the call from baresip to the outgoing test number, which answers
/// by itself, so the app can merge the two and drop out.
Future<void> _userCanTransferACall(CallingRobot robot) async {
  final baresip = await BaresipClient.connect();

  try {
    await baresip.dial(TestEnv.integrationTestIncomingCallNumber);

    await robot.waitForIncomingCallToRing();
    await robot.answerIncomingCall();
    await robot.waitForAnsweredCallToConnect();
    await robot.transferTo(TestEnv.integrationTestCallingPhoneNumber);
    await robot.verifyCallScreenIsDismissed();
  } finally {
    // After the transfer baresip is in a call with the transfer target.
    await baresip.hangupAll();
    await baresip.close();
  }
}

Future<void> _userCanDeclineACall(
  WidgetTester tester,
  CallingRobot robot,
) async {
  final baresip = await BaresipClient.connect();

  try {
    await baresip.dial(TestEnv.integrationTestIncomingCallNumber);

    await robot.waitForIncomingCallToRing();
    robot.verifyCallIsIncoming();
    await robot.ringFor(const Duration(seconds: 3));
    await robot.declineIncomingCall();
    await robot.waitForDeclinedCallToEnd();

    await tester.pumpUntil(
      () => baresip.hasSeenCallClosed,
      reason: 'baresip should see its call end once the app declines it',
      settle: false,
    );
  } finally {
    await baresip.hangup();
    await baresip.close();
  }
}

Future<void> _unansweredCallIsMissed(
  WidgetTester tester,
  CallingRobot robot,
) async {
  // The call declined just before is also unanswered, so only a call that
  // wasn't in the history yet counts.
  final earlierMissedCallIds = await _missedCallIds();
  final baresip = await BaresipClient.connect();

  try {
    await baresip.dial(TestEnv.integrationTestIncomingCallNumber);

    await robot.waitForIncomingCallToRing();
    await robot.ringFor(const Duration(seconds: 5));
    await baresip.hangup();
    await robot.waitForMissedCallToEnd();
  } finally {
    await baresip.hangup();
    await baresip.close();
  }

  await _verifyNewMissedCallIsInHistory(tester, earlierMissedCallIds);
}

Future<Set<String>> _missedCallIds() async {
  final missedCalls = await dependencyLocator<RecentCallRepository>()
      .getRecentCalls(page: 1, onlyMissedCalls: true);
  return missedCalls.map((call) => call.id).toSet();
}

/// The call history API can take a while to include a call that just ended.
Future<void> _verifyNewMissedCallIsInHistory(
  WidgetTester tester,
  Set<String> earlierMissedCallIds,
) async {
  const attempts = 12;
  const interval = Duration(seconds: 5);

  for (var i = 0; i < attempts; i++) {
    final missedCallIds = await _missedCallIds();
    if (missedCallIds.difference(earlierMissedCallIds).isNotEmpty) return;

    await tester.pumpFor(interval);
  }

  fail(
    'The call baresip hung up before it was answered should be in the call '
    'history as missed, but it was not within ${interval * attempts}',
  );
}
