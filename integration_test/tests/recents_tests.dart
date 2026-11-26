import 'package:flutter_test/flutter_test.dart';
import 'package:vialer/presentation/features/recent/widgets/popup_menu.dart';

import '../robots/calling_robot.dart';
import '../robots/recents_robot.dart';
import '../utils/test_env.dart';
import '../utils/test_extensions.dart';
import '../utils/test_log.dart';

Future<void> runRecentsTests(IntegrationTestContext context) async {
  TestLog.group('🕘', 'Recents');

  await context.tester.navigateToRecentsTab();

  final robot = RecentsRobot(context.tester);

  await TestLog.test(
    'User can see their recent calls',
    () => _userCanSeeTheirRecentCalls(context, robot),
  );
  await TestLog.test(
    'User can copy the number of a call',
    () => _userCanCopyTheNumberOfACall(robot),
  );
  await TestLog.test(
    'User can view the details of a call',
    () => _userCanViewTheDetailsOfACall(robot),
  );
  await TestLog.test(
    'User can show only missed calls',
    () => _userCanShowOnlyMissedCalls(robot),
  );
  await TestLog.test(
    'User can switch between personal and all calls',
    () => _userCanSwitchBetweenPersonalAndAllCalls(robot),
  );
  await TestLog.test(
    'User can add a caller as shared contact',
    () => _userCanAddACallerAsSharedContact(robot),
  );

  if (_placedOutgoingCallEarlier(context.config)) {
    await TestLog.test(
      'User can call back',
      () => _userCanCallBack(context, robot),
    );
  } else {
    TestLog.skip(
      'User can call back',
      because:
          'this device cannot place a real call, or no call to the calling '
          'test number was placed in this run',
    );
  }
}

/// Whether the outgoing call tests ran earlier, leaving a fresh call to the
/// calling test number in the history.
bool _placedOutgoingCallEarlier(TestConfiguration config) =>
    config.canPlaceRealCalls && config.suite.everythingExceptIncomingCalls;

Future<void> _userCanSeeTheirRecentCalls(
  IntegrationTestContext context,
  RecentsRobot robot,
) async {
  await robot.waitForCallsToLoad();
  robot.verifyCallsAreShown();

  if (!_placedOutgoingCallEarlier(context.config)) return;

  TestLog.step(
    '🔎',
    'Expecting the call to ${TestEnv.integrationTestCallingPhoneNumber} '
        'near the top',
  );
  await robot.verifyOutgoingCallIsNearTheTop(
    TestEnv.integrationTestCallingPhoneNumber,
    placedAfter: DateTime.now().subtract(const Duration(hours: 1)),
  );
}

Future<void> _userCanCopyTheNumberOfACall(RecentsRobot robot) async {
  final call = robot.topCall;
  TestLog.detail('Number of the top call', call.thirdPartyNumber);

  await robot.clearClipboard();
  await robot.openCallMenuAndSelect(call, RecentCallMenuAction.copy);
  robot.verifyNumberCopiedMessageIsShown();
  await robot.verifyClipboardContains(call.thirdPartyNumber);
  await robot.waitForSnackBarToDismiss();
}

Future<void> _userCanViewTheDetailsOfACall(RecentsRobot robot) async {
  final call = robot.topCall;
  TestLog.detail('Number of the top call', call.thirdPartyNumber);
  TestLog.detail('Placed at', call.date);

  await robot.openCallMenuAndSelect(call, RecentCallMenuAction.callDetails);
  await robot.verifyCallDetailsAreShownFor(call);
  await robot.closeCallDetails();
  robot.verifyIsOnHomeScreen();
}

Future<void> _userCanShowOnlyMissedCalls(RecentsRobot robot) async {
  final hadMissedCalls = robot.showsMissedCalls;
  final hadAnsweredCalls = robot.showsAnsweredCalls;
  TestLog.detail('Missed calls shown', hadMissedCalls);
  TestLog.detail('Answered calls shown', hadAnsweredCalls);

  await robot.turnOnMissedCallsOnly();
  try {
    await robot.verifyOnlyMissedCallsAreShown(expectAnyCalls: hadMissedCalls);
  } finally {
    await robot.turnOffMissedCallsOnly();
  }

  if (hadAnsweredCalls) await robot.verifyAnsweredCallsAreShownAgain();
}

/// The tabs only show for users allowed to see the calls of their whole
/// client, and only once they turned that on in the settings.
Future<void> _userCanSwitchBetweenPersonalAndAllCalls(
  RecentsRobot robot,
) async {
  if (!robot.canSeeClientCalls) {
    TestLog.step(
      'ℹ️',
      'The test user may not see client calls, so only checking that the '
          'personal and all calls tabs are hidden',
    );
    robot.verifyCallTabsAreHidden();
    return;
  }

  final wasEnabled = robot.showClientCallsSetting;
  TestLog.detail('Showed client calls before', wasEnabled);
  if (!wasEnabled) await robot.setShowClientCalls(enabled: true);

  try {
    await robot.waitForCallsToLoad();
    robot.verifyCallTabsAreShown();

    await robot.tapAllCallsTab();
    await robot.verifyClientCallsAreShown();

    await robot.tapPersonalCallsTab();
    await robot.verifyPersonalCallsAreShown();
  } finally {
    if (!wasEnabled) await robot.setShowClientCalls(enabled: false);
  }

  robot.verifyCallTabsAreHidden();
  await robot.waitForCallsToLoad();
}

/// Once added, the call shows the contact's name and opens it from its menu,
/// which is also where it is deleted again.
Future<void> _userCanAddACallerAsSharedContact(RecentsRobot robot) async {
  final call = robot.callToAddAsSharedContact(
    preferredNumber: TestEnv.integrationTestCallingPhoneNumber,
  );
  if (call == null) {
    throw TestFailure(
      'A call with an outside number that is not a contact yet should be '
      'shown, to add as shared contact',
    );
  }

  final name =
      '${RecentsRobot.sharedContactNamePrefix} '
      '${DateTime.now().millisecondsSinceEpoch}';

  TestLog.detail('Number of the call', call.thirdPartyNumber);
  TestLog.detail('Shared contact', name);

  try {
    await robot.openCallMenuAndSelect(
      call,
      RecentCallMenuAction.addSharedContact,
    );
    await robot.verifySharedContactFormIsPrefilledWith(call.thirdPartyNumber);
    await robot.enterSharedContactName(name);
    await robot.saveSharedContact();
    await robot.waitForCallToShowName(name);

    await robot.openCallMenuAndSelect(
      robot.callShowingName(name),
      RecentCallMenuAction.viewContact,
    );
    await robot.verifyContactDetailsShowName(name);
    await robot.tapEditContactButton();
    await robot.deleteSharedContact();
    robot.verifyIsOnHomeScreen();

    await robot.verifyNoCallShowsName(name);
  } finally {
    await robot.deleteLeftoverSharedContacts();
  }
}

/// Only calls back the calling test number, never a number from the history
/// that may belong to someone real.
Future<void> _userCanCallBack(
  IntegrationTestContext context,
  RecentsRobot robot,
) async {
  final call = robot.outgoingCallTo(TestEnv.integrationTestCallingPhoneNumber);
  if (call == null) {
    throw TestFailure(
      'The call to ${TestEnv.integrationTestCallingPhoneNumber} placed earlier '
      'should be shown, to call it back',
    );
  }

  final callingRobot = CallingRobot(context.tester, context.config);
  final calledAfter = DateTime.now().subtract(const Duration(minutes: 1));

  TestLog.step('☎️', 'Calling back ${call.thirdPartyNumber}');
  await robot.openCallMenuAndSelect(call, RecentCallMenuAction.call);
  await callingRobot.waitForCallToConnect();
  await callingRobot.verifyCallDuration();
  TestLog.step('🔴', 'Hanging up');
  await callingRobot.tapHangUpButton();
  await callingRobot.verifyCallScreenIsDismissed();

  await robot.verifyOutgoingCallIsNearTheTop(
    TestEnv.integrationTestCallingPhoneNumber,
    placedAfter: calledAfter,
  );
}
