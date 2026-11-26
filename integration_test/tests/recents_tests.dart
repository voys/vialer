import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vialer/presentation/features/recent/widgets/popup_menu.dart';

import '../robots/calling_robot.dart';
import '../robots/recents_robot.dart';
import '../utils/test_env.dart';
import '../utils/test_extensions.dart';

Future<void> runRecentsTests(IntegrationTestContext context) async {
  await context.tester.navigateToRecentsTab();

  final robot = RecentsRobot(context.tester);

  await _userCanSeeTheirRecentCalls(context, robot);
  await _userCanCopyTheNumberOfACall(robot);
  await _userCanViewTheDetailsOfACall(robot);
  await _userCanShowOnlyMissedCalls(robot);
  await _userCanSwitchBetweenPersonalAndAllCalls(robot);
  await _userCanAddACallerAsSharedContact(robot);
  await _userCanCallBack(context, robot);
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

  await robot.verifyOutgoingCallIsNearTheTop(
    TestEnv.integrationTestCallingPhoneNumber,
    placedAfter: DateTime.now().subtract(const Duration(hours: 1)),
  );
}

Future<void> _userCanCopyTheNumberOfACall(RecentsRobot robot) async {
  final call = robot.topCall;

  await robot.clearClipboard();
  await robot.openCallMenuAndSelect(call, RecentCallMenuAction.copy);
  robot.verifyNumberCopiedMessageIsShown();
  await robot.verifyClipboardContains(call.thirdPartyNumber);
  await robot.waitForSnackBarToDismiss();
}

Future<void> _userCanViewTheDetailsOfACall(RecentsRobot robot) async {
  final call = robot.topCall;

  await robot.openCallMenuAndSelect(call, RecentCallMenuAction.callDetails);
  await robot.verifyCallDetailsAreShownFor(call);
  await robot.closeCallDetails();
  robot.verifyIsOnHomeScreen();
}

Future<void> _userCanShowOnlyMissedCalls(RecentsRobot robot) async {
  final hadMissedCalls = robot.showsMissedCalls;
  final hadAnsweredCalls = robot.showsAnsweredCalls;

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
    debugPrint(
      'The test user may not see client calls, so only checking that the '
      'personal and all calls tabs are hidden.',
    );
    robot.verifyCallTabsAreHidden();
    return;
  }

  final wasEnabled = robot.showClientCallsSetting;
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
    debugPrint(
      'Skipping adding a caller as shared contact: none of the shown calls is '
      'with an outside number that is not a contact yet.',
    );
    return;
  }

  final name =
      '${RecentsRobot.sharedContactNamePrefix} '
      '${DateTime.now().millisecondsSinceEpoch}';

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
  if (!_placedOutgoingCallEarlier(context.config)) {
    debugPrint(
      'Skipping calling back from recents: this device cannot place a real '
      'call, or no call to the calling test number was placed in this run.',
    );
    return;
  }

  final call = robot.outgoingCallTo(TestEnv.integrationTestCallingPhoneNumber);
  if (call == null) {
    throw TestFailure(
      'The call to ${TestEnv.integrationTestCallingPhoneNumber} placed earlier '
      'should be shown, to call it back',
    );
  }

  final callingRobot = CallingRobot(context.tester, context.config);
  final calledAfter = DateTime.now().subtract(const Duration(minutes: 1));

  await robot.openCallMenuAndSelect(call, RecentCallMenuAction.call);
  await callingRobot.waitForCallToConnect();
  await callingRobot.verifyCallDuration();
  await callingRobot.tapHangUpButton();
  await callingRobot.verifyCallScreenIsDismissed();

  await robot.verifyOutgoingCallIsNearTheTop(
    TestEnv.integrationTestCallingPhoneNumber,
    placedAfter: calledAfter,
  );
}
