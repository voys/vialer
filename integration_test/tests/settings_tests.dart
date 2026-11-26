import 'dart:io' show Platform;

import 'package:flutter_test/flutter_test.dart';
import 'package:vialer/data/models/calling/outgoing_number/outgoing_number.dart';
import 'package:vialer/data/models/relations/user_availability_status.dart';
import 'package:vialer/presentation/features/settings/widgets/availability/ringing_device/widget.dart'
    show RingingDeviceType;
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
import '../utils/test_log.dart';

/// Runs before the call tests, so everything changed here is put back, with
/// the account left online and ringing on this device.
Future<void> runSettingsTests(IntegrationTestContext context) async {
  final tester = context.tester;

  TestLog.group('⚙️', 'Settings');

  await tester.navigateToSettingsTab();

  final robot = SettingsRobot(tester);

  await TestLog.test(
    'User can change their availability status',
    () => _userCanChangeTheirAvailabilityStatus(robot),
  );
  await TestLog.test(
    'User can change their ringing device',
    () => _userCanChangeTheirRingingDevice(robot),
  );

  final wasTroubleshootingUnlocked = robot.isTroubleshootingUnlocked;
  try {
    await TestLog.test(
      'User can view information about the app',
      () => _userCanViewInformationAboutTheApp(robot),
    );
    await TestLog.test(
      'User can change their app preferences',
      () => _userCanChangeTheirAppPreferences(robot),
    );
  } finally {
    await robot.restoreTroubleshootingUnlocked(
      unlocked: wasTroubleshootingUnlocked,
    );
  }

  await TestLog.test(
    'User can manage their account',
    () => _userCanManageTheirAccount(robot),
  );
  await TestLog.test(
    'User can manage their client',
    () => _userCanManageTheirClient(robot),
  );

  if (robot.canOpenSystemPage) {
    await TestLog.test(
      'User can view system information',
      () => _userCanViewSystemInformation(robot),
    );
  } else {
    TestLog.skip(
      'User can view system information',
      because: 'the system page is not in production builds',
    );
  }

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
      TestLog.step('🚦', 'Selecting ${status.name}');
      await robot.selectAvailabilityStatus(status);
      robot.verifyAvailabilityStatusIs(status);
    }
  } finally {
    await robot.restoreAvailabilityStatus(UserAvailabilityStatus.online);
  }
}

/// Ends ringing in this app, whatever it started on: the call tests need
/// that, and going offline in the availability test can leave no device
/// selected at all.
Future<void> _userCanChangeTheirRingingDevice(SettingsRobot robot) async {
  final onlineDevices = robot.otherRingingDevices(online: true);
  final offlineDevices = robot.otherRingingDevices(online: false);
  TestLog.detail('Ringing devices', robot.ringingDevicesDescription);

  if (onlineDevices.isEmpty && offlineDevices.isEmpty) {
    throw TestFailure(
      'The test account should have another device besides this app, but '
      'has: ${robot.ringingDevicesDescription}',
    );
  }

  try {
    for (final device in offlineDevices) {
      TestLog.step('📵', 'Expecting a warning for the offline ${device.name}');
      await robot.tapOfflineRingingDeviceAndVerifyWarning(device);
    }

    for (final device in onlineDevices) {
      TestLog.step('🔔', 'Ringing on the ${device.name}');
      await robot.selectRingingDevice(device);
      robot.verifyRingingDeviceIs(device);
    }

    TestLog.step('🔔', 'Ringing in this app');
    await robot.selectRingingDevice(RingingDeviceType.mobile);
    robot.verifyRingingDeviceIs(RingingDeviceType.mobile);
  } finally {
    await robot.restoreRingingDeviceToThisApp();
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
    TestLog.step('🔓', 'Unlocking troubleshooting through the build info');
    await robot.unlockTroubleshootingThroughBuildInfo();
    await robot.verifyTroubleshootingIsUnlocked();
  }
}

Future<void> _userCanChangeTheirAppPreferences(SettingsRobot robot) async {
  await robot.openAppPreferences();
  TestLog.detail('Allowed VoIP calling', robot.isAllowedVoipCalling);
  TestLog.detail('Troubleshooting unlocked', robot.isTroubleshootingUnlocked);

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
      TestLog.step('🎚️', 'Calibrating echo cancellation');
      await robot.performEchoCancellationCalibration();
    }
  }

  await robot.closeTroubleshootingPage();
}

Future<void> _userCanManageTheirAccount(SettingsRobot robot) async {
  await robot.openUserPage();

  TestLog.detail('Username', TestEnv.integrationTestUser1Username);
  await robot.verifyUsernameIs(TestEnv.integrationTestUser1Username);
  await _userCanChangeTheirMobileNumber(robot);
  await _userCanChangeTheirOutgoingNumber(robot);

  await robot.closeUserPage();
}

/// An account without a mobile number can't get back to that through the
/// app, so it is only put back around it.
Future<void> _userCanChangeTheirMobileNumber(SettingsRobot robot) async {
  final original = robot.currentMobileNumber;
  final other = original == fakeMobileNumber
      ? otherFakeMobileNumber
      : fakeMobileNumber;

  try {
    TestLog.step('📱', 'Changing the mobile number from $original to $other');
    await robot.changeMobileNumber(other);
    robot.verifyMobileNumberIs(other);

    if (await robot.canEnterMobileNumber(original)) {
      TestLog.step('↩️', 'Changing the mobile number back to $original');
      await robot.changeMobileNumber(original);
      robot.verifyMobileNumberIs(original);
    }
  } finally {
    await robot.restoreMobileNumber(original);
  }
}

Future<void> _userCanChangeTheirOutgoingNumber(SettingsRobot robot) async {
  if (!robot.canChangeOutgoingNumber) {
    throw TestFailure(
      'The test account should be allowed to change its outgoing number',
    );
  }

  final original = robot.currentOutgoingNumber;
  final other = robot.otherOutgoingNumber;

  if (other == null) {
    throw TestFailure(
      'The test account should have an outgoing number to change to, and its '
      'current one ($original) should be offered to change back to',
    );
  }

  try {
    TestLog.step(
      '📤',
      'Changing the outgoing number from ${original.forLog} to '
          '${other.forLog}',
    );
    await robot.changeOutgoingNumber(other);
    robot.verifyOutgoingNumberIs(other);

    TestLog.step('↩️', 'Changing the outgoing number back');
    await robot.changeOutgoingNumber(original);
    robot.verifyOutgoingNumberIs(original);
  } finally {
    await robot.restoreOutgoingNumber(original);
  }
}

Future<void> _userCanManageTheirClient(SettingsRobot robot) async {
  if (!robot.canOpenClientPage) {
    throw TestFailure(
      'The test account should have the permissions to see the client page',
    );
  }

  await robot.openClientPage();

  if (!robot.canChangeTemporaryRedirect) {
    throw TestFailure(
      'The test account should be allowed to change the temporary redirect',
    );
  }
  await _userCanStartAndStopATemporaryRedirect(robot);

  for (final link in [
    CallsLinkTile,
    DialPlanLinkTile,
    OpeningHoursLinkTile,
    StatsLinkTile,
  ]) {
    TestLog.step('🔗', 'Opening $link');
    if (!await robot.openPortalLinkAndReturn(link)) {
      throw TestFailure('The test account should be allowed to see $link');
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
      TestLog.step('🧹', 'Stopping a redirect left behind by an earlier run');
      await robot.stopTemporaryRedirect();
    }

    if (!robot.hasTemporaryRedirectDestinations) {
      throw TestFailure(
        "The test account's client should have a voicemail to temporarily "
        'redirect to',
      );
    }

    TestLog.step('↪️', 'Starting a temporary redirect to voicemail');
    await robot.startTemporaryRedirect();
    robot.verifyTemporaryRedirectIsShown();

    TestLog.step('⏹️', 'Stopping the temporary redirect');
    await robot.stopTemporaryRedirect();
    robot.verifyNoTemporaryRedirectIsShown();
  } finally {
    await robot.restoreNoTemporaryRedirect();
  }
}

Future<void> _userCanViewSystemInformation(SettingsRobot robot) async {
  await robot.openSystemPage();

  await robot.viewLogs();
  await robot.viewFeatureFlags();
  await robot.viewVersionInfo();

  await robot.closeSystemPage();
}

extension on OutgoingNumber {
  String get forLog => isSuppressed ? 'suppressed' : valueOrEmpty;
}
