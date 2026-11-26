import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:vialer/data/models/relations/user_availability_status.dart';
import 'package:vialer/presentation/features/settings/widgets/tile/always_show_caller_name_in_recents.dart';
import 'package:vialer/presentation/features/settings/widgets/tile/enable_advanced_voip_logging.dart';
import 'package:vialer/presentation/features/settings/widgets/tile/link/calls.dart';
import 'package:vialer/presentation/features/settings/widgets/tile/link/dial_plan.dart';
import 'package:vialer/presentation/features/settings/widgets/tile/link/opening_hours.dart';
import 'package:vialer/presentation/features/settings/widgets/tile/link/stats.dart';
import 'package:vialer/presentation/features/settings/widgets/tile/remote_logging.dart';
import 'package:vialer/presentation/features/settings/widgets/tile/show_calls_in_native_recents.dart';
import 'package:vialer/presentation/features/settings/widgets/tile/show_client_calls.dart';
import 'package:vialer/presentation/features/settings/widgets/tile/use_mobile_number_as_fallback.dart';
import 'package:vialer/presentation/features/settings/widgets/tile/use_phone_ringtone.dart';

import '../robots/settings_robot.dart';
import '../utils/test_env.dart';
import '../utils/test_extensions.dart';

/// Runs before the call tests, so everything changed here is put back, with
/// the account left online and ringing on this device.
Future<void> runSettingsTests(IntegrationTestContext context) async {
  final tester = context.tester;
  await tester.navigateToSettingsTab();

  final robot = SettingsRobot(tester);

  await _userCanChangeTheirAvailabilityStatus(robot);
  await _userCanChangeTheirRingingDevice(robot);

  final wasTroubleshootingUnlocked = robot.isTroubleshootingUnlocked;
  try {
    await _userCanViewInformationAboutTheApp(robot);
    await _userCanChangeTheirAppPreferences(robot);
  } finally {
    await robot.restoreTroubleshootingUnlocked(
      unlocked: wasTroubleshootingUnlocked,
    );
  }

  await _userCanManageTheirAccount(robot);
  await _userCanManageTheirClient(robot);
  await _userCanViewSystemInformation(robot);

  // Switching tabs also pops any settings page still open.
  await tester.navigateToContactsTab();
}

/// Ends online rather than on whatever status it started with: the call tests
/// can't receive calls otherwise, so a status left behind by an earlier,
/// failed run is better corrected than kept.
Future<void> _userCanChangeTheirAvailabilityStatus(SettingsRobot robot) async {
  try {
    for (final status in [
      UserAvailabilityStatus.availableForColleagues,
      UserAvailabilityStatus.doNotDisturb,
      UserAvailabilityStatus.offline,
      UserAvailabilityStatus.online,
    ]) {
      await robot.selectAvailabilityStatus(status);
      robot.verifyAvailabilityStatusIs(status);
    }
  } finally {
    await robot.restoreAvailabilityStatus(UserAvailabilityStatus.online);
  }
}

Future<void> _userCanChangeTheirRingingDevice(SettingsRobot robot) async {
  final originalDevice = robot.currentRingingDevice;
  final originalDestination = robot.currentDestination;
  final otherDevice = robot.otherAvailableRingingDevice;

  if (otherDevice == null) {
    debugPrint(
      'Skipping changing the ringing device: the user has no other device '
      'that can ring',
    );
    return;
  }

  try {
    await robot.selectRingingDevice(otherDevice);
    robot.verifyRingingDeviceIs(otherDevice);

    await robot.selectRingingDevice(originalDevice);
    robot.verifyRingingDeviceIs(originalDevice);
  } finally {
    await robot.restoreDestination(originalDestination);
  }
}

/// Also unlocks the troubleshooting settings, which the app preferences test
/// covers next.
Future<void> _userCanViewInformationAboutTheApp(SettingsRobot robot) async {
  await robot.openAboutPage();
  robot.verifyAboutPageIsShown();
  await robot.verifyBuildInfoIsShown();

  // The privacy policy opens in the browser, outside the app, so it is only
  // checked to be there.
  await robot.openFeatureAnnouncementsAndReturn();

  if (robot.isTroubleshootingUnlocked) {
    await robot.closeAboutPage();
  } else {
    await robot.unlockTroubleshootingThroughBuildInfo();
    await robot.verifyTroubleshootingIsUnlocked();
  }
}

Future<void> _userCanChangeTheirAppPreferences(SettingsRobot robot) async {
  await robot.openAppPreferences();

  if (robot.isAllowedVoipCalling) {
    await robot.toggleUseVoipOffAndOn();
    await robot.togglePreferenceAndBack(UseMobileNumberAsFallbackTile);

    if (Platform.isIOS) {
      await robot.togglePreferenceAndBack(ShowCallsInNativeRecentsTile);
    }
  }

  if (Platform.isAndroid) {
    await robot.verifyIgnoreBatteryOptimizationsIsOffered();
  }

  await robot.togglePreferenceAndBack(ShowClientCallsTile);
  await robot.togglePreferenceAndBack(AlwaysShowCallerNameInRecentsTile);

  if (robot.isAllowedVoipCalling) {
    await robot.togglePreferenceAndBack(UsePhoneRingtoneTile);
  }

  await robot.togglePreferenceAndBack(RemoteLoggingTile);

  if (robot.isTroubleshootingUnlocked) {
    await _userCanCalibrateEchoCancellation(robot);

    if (Platform.isAndroid) {
      await robot.togglePreferenceAndBack(EnableAdvancedVoipLoggingTile);
    }
  }

  await robot.closeAppPreferences();
}

Future<void> _userCanCalibrateEchoCancellation(SettingsRobot robot) async {
  await robot.openTroubleshootingPage();

  if (robot.isAllowedVoipCalling) {
    robot.verifyEchoCancellationCalibrationIsShown();

    // On the iOS simulator starting the audio this needs takes the app down.
    if (Platform.isAndroid) {
      await robot.performEchoCancellationCalibration();
    }
  }

  await robot.closeTroubleshootingPage();
}

Future<void> _userCanManageTheirAccount(SettingsRobot robot) async {
  await robot.openUserPage();

  await robot.verifyUsernameIs(TestEnv.integrationTestUser1Username);
  await _userCanChangeTheirMobileNumber(robot);
  await _userCanChangeTheirOutgoingNumber(robot);

  await robot.closeUserPage();
}

Future<void> _userCanChangeTheirMobileNumber(SettingsRobot robot) async {
  final original = robot.currentMobileNumber;
  final other = await robot.findAnotherValidMobileNumber();

  if (other == null) {
    debugPrint(
      'Skipping changing the mobile number: "$original" could not be entered '
      'again afterwards',
    );
    return;
  }

  try {
    await robot.changeMobileNumber(other);
    robot.verifyMobileNumberIs(other);

    await robot.changeMobileNumber(original);
    robot.verifyMobileNumberIs(original);
  } finally {
    await robot.restoreMobileNumber(original);
  }
}

Future<void> _userCanChangeTheirOutgoingNumber(SettingsRobot robot) async {
  if (!robot.canChangeOutgoingNumber) {
    debugPrint(
      'Skipping changing the outgoing number: the user is not allowed to',
    );
    return;
  }

  final original = robot.currentOutgoingNumber;
  final other = robot.otherOutgoingNumber;

  if (other == null) {
    debugPrint(
      'Skipping changing the outgoing number: there is no other option, or '
      'the current one could not be picked again',
    );
    return;
  }

  try {
    await robot.changeOutgoingNumber(other);
    robot.verifyOutgoingNumberIs(other);

    await robot.changeOutgoingNumber(original);
    robot.verifyOutgoingNumberIs(original);
  } finally {
    await robot.restoreOutgoingNumber(original);
  }
}

Future<void> _userCanManageTheirClient(SettingsRobot robot) async {
  if (!robot.canOpenClientPage) {
    debugPrint(
      'Skipping the client page: the user has none of the permissions for it',
    );
    return;
  }

  await robot.openClientPage();

  if (robot.canChangeTemporaryRedirect) {
    await _userCanStartAndStopATemporaryRedirect(robot);
  }

  for (final link in [
    CallsLinkTile,
    DialPlanLinkTile,
    OpeningHoursLinkTile,
    StatsLinkTile,
  ]) {
    if (!await robot.openPortalLinkAndReturn(link)) {
      debugPrint('Skipping $link: the user is not allowed to see it');
    }
  }

  await robot.closeClientPage();
}

/// An active redirect sends incoming calls to voicemail, so none may be left
/// behind for the incoming call tests.
Future<void> _userCanStartAndStopATemporaryRedirect(SettingsRobot robot) async {
  try {
    // Left behind by an earlier run that failed halfway.
    if (robot.hasTemporaryRedirect) {
      await robot.stopTemporaryRedirect();
    }

    if (!robot.hasTemporaryRedirectDestinations) {
      debugPrint(
        'Skipping starting a temporary redirect: the client has no voicemail '
        'to redirect to',
      );
      return;
    }

    await robot.startTemporaryRedirect();
    robot.verifyTemporaryRedirectIsShown();

    await robot.stopTemporaryRedirect();
    robot.verifyNoTemporaryRedirectIsShown();
  } finally {
    await robot.restoreNoTemporaryRedirect();
  }
}

Future<void> _userCanViewSystemInformation(SettingsRobot robot) async {
  if (!robot.canOpenSystemPage) {
    debugPrint('Skipping the system page: it is not in production builds');
    return;
  }

  await robot.openSystemPage();

  await robot.viewLogs();
  await robot.viewFeatureFlags();
  await robot.viewVersionInfo();

  await robot.closeSystemPage();
}
