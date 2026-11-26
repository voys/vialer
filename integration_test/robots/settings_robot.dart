import 'dart:io' show Platform;

import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoDatePicker;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vialer/data/models/business_availability/temporary_redirect/temporary_redirect.dart'
    show Display, TemporaryRedirectDestination;
import 'package:vialer/data/models/calling/outgoing_number/outgoing_number.dart';
import 'package:vialer/data/models/calling/voip/destination.dart'
    show Destination, DestinationsList, IsOnline;
import 'package:vialer/data/models/feature/feature.dart';
import 'package:vialer/data/models/relations/user_availability_status.dart';
import 'package:vialer/data/models/user/settings/app_setting.dart';
import 'package:vialer/data/models/user/settings/call_setting.dart';
import 'package:vialer/data/models/user/settings/settings.dart';
import 'package:vialer/data/models/user/user.dart';
import 'package:vialer/domain/usecases/business_availability/temporary_redirect/cancel_current_temporary_redirect.dart';
import 'package:vialer/domain/usecases/phone_numbers/strictly_validate_mobile_phone_number.dart';
import 'package:vialer/presentation/features/business_availability/controllers/temporary_redirect/cubit.dart';
import 'package:vialer/presentation/features/business_availability/pages/temporary_redirect/page.dart';
import 'package:vialer/presentation/features/business_availability/widgets/temporary_redirect/date_field.dart';
import 'package:vialer/presentation/features/business_availability/widgets/temporary_redirect/field.dart';
import 'package:vialer/presentation/features/business_availability/widgets/temporary_redirect/setting_tile.dart';
import 'package:vialer/presentation/features/call/widgets/outgoing_number_prompt/item.dart';
import 'package:vialer/presentation/features/settings/controllers/cubit.dart';
import 'package:vialer/presentation/features/settings/pages/about_the_app.dart';
import 'package:vialer/presentation/features/settings/pages/app_preferences.dart';
import 'package:vialer/presentation/features/settings/pages/client.dart';
import 'package:vialer/presentation/features/settings/pages/settings.dart';
import 'package:vialer/presentation/features/settings/pages/system/feature_flags.dart';
import 'package:vialer/presentation/features/settings/pages/system/logs.dart';
import 'package:vialer/presentation/features/settings/pages/system/system.dart';
import 'package:vialer/presentation/features/settings/pages/system/version_info.dart';
import 'package:vialer/presentation/features/settings/pages/troubleshooting.dart';
import 'package:vialer/presentation/features/settings/pages/user.dart';
import 'package:vialer/presentation/features/settings/widgets/availability/availability_status/availability_status_button.dart';
import 'package:vialer/presentation/features/settings/widgets/availability/button.dart';
import 'package:vialer/presentation/features/settings/widgets/availability/ringing_device/ringing_device_button.dart';
import 'package:vialer/presentation/features/settings/widgets/availability/ringing_device/widget.dart';
import 'package:vialer/presentation/features/settings/widgets/settings_button.dart';
import 'package:vialer/presentation/features/settings/widgets/tile/build_info.dart';
import 'package:vialer/presentation/features/settings/widgets/tile/dialog/edit_mobile_number_dialog.dart';
import 'package:vialer/presentation/features/settings/widgets/tile/dialog/edit_outgoing_number_dialog.dart';
import 'package:vialer/presentation/features/settings/widgets/tile/echo_cancellation_calibration.dart';
import 'package:vialer/presentation/features/settings/widgets/tile/feature_announcement.dart';
import 'package:vialer/presentation/features/settings/widgets/tile/ignore_battery_optimizations.dart';
import 'package:vialer/presentation/features/settings/widgets/tile/link/sub_page.dart';
import 'package:vialer/presentation/features/settings/widgets/tile/link/troubleshooting.dart';
import 'package:vialer/presentation/features/settings/widgets/tile/mobile_number.dart';
import 'package:vialer/presentation/features/settings/widgets/tile/outgoing_number.dart';
import 'package:vialer/presentation/features/settings/widgets/tile/privacy_policy.dart';
import 'package:vialer/presentation/features/settings/widgets/tile/use_mobile_number_as_fallback.dart';
import 'package:vialer/presentation/features/settings/widgets/tile/use_voip.dart';
import 'package:vialer/presentation/features/settings/widgets/tile/username.dart';
import 'package:vialer/presentation/features/settings/widgets/tile/value.dart';
import 'package:vialer/presentation/features/settings/widgets/tile/widget.dart';
import 'package:vialer/presentation/shared/controllers/user_availability_status_builder/cubit.dart';
import 'package:vialer/presentation/shared/pages/web_view.dart';
import 'package:vialer/presentation/shared/widgets/stylized_switch.dart';
import 'package:vialer/version_info.vialer.dart';

import '../utils/test_extensions.dart';
import 'integration_test_robot.dart';

class SettingsRobot extends IntegrationTestRobot {
  SettingsRobot(super.tester);

  /// Remote changes are refused for a minute once VoIPGRID rate limits us, so
  /// waiting for them has to outlast that.
  static const _remoteChangeTimeout = Duration(seconds: 90);

  SettingsCubit get _settings => _settingsPageElement.read<SettingsCubit>();

  UserAvailabilityStatusCubit get _availability =>
      _settingsPageElement.read<UserAvailabilityStatusCubit>();

  TemporaryRedirectCubit get _temporaryRedirects => tester
      .element(find.byType(Navigator).first)
      .read<TemporaryRedirectCubit>();

  // The settings tab is offstage while a page is pushed on the root navigator,
  // such as a web view, but its cubits are still needed then.
  BuildContext get _settingsPageElement =>
      tester.element(find.byType(SettingsPage, skipOffstage: false));

  User get _user => _settings.state.user;

  // Sub pages

  Future<void> openAppPreferences() => _openSubPage(
    FontAwesomeIcons.solidMobileNotch,
    find.byType(AppPreferencesSubPage),
  );

  Future<void> closeAppPreferences() =>
      _closePage(find.byType(AppPreferencesSubPage));

  Future<void> openUserPage() =>
      _openSubPage(FontAwesomeIcons.circleUser, find.byType(UserSubPage));

  Future<void> closeUserPage() => _closePage(find.byType(UserSubPage));

  /// Only users with permissions for at least one of its settings get to see
  /// the client page.
  bool get canOpenClientPage => tester.any(
    _subPageLink(FontAwesomeIcons.building),
  );

  Future<void> openClientPage() =>
      _openSubPage(FontAwesomeIcons.building, find.byType(ClientSubPage));

  Future<void> closeClientPage() => _closePage(find.byType(ClientSubPage));

  Future<void> openAboutPage() => _openSubPage(
    FontAwesomeIcons.circleInfo,
    find.byType(AboutTheAppSubPage),
  );

  Future<void> closeAboutPage() => _closePage(find.byType(AboutTheAppSubPage));

  /// The system page is left out of production builds.
  bool get canOpenSystemPage => tester.any(
    _subPageLink(FontAwesomeIcons.roadBarrier),
  );

  Future<void> openSystemPage() =>
      _openSubPage(FontAwesomeIcons.roadBarrier, find.byType(SystemSubPage));

  Future<void> closeSystemPage() => _closePage(find.byType(SystemSubPage));

  Finder _subPageLink(FaIconData icon) => find.byWidgetPredicate(
    (widget) => widget is SubPageLinkTile && widget.icon == icon,
  );

  Future<void> _openSubPage(FaIconData icon, Finder page) async {
    final link = _subPageLink(icon);
    await tester.ensureVisible(link);
    await tester.pumpAndSettle();
    await tester.tap(link);
    await tester.pumpUntilFound(page, reason: '$page should open');
  }

  /// Goes back through the page's own back button, rather than
  /// [WidgetTester.pageBack], which looks for an English tooltip.
  Future<void> _closePage(Finder page) async {
    await tester.tap(
      find.descendant(of: page, matching: find.byType(BackButton)).first,
    );
    await tester.pumpUntilGone(page, reason: '$page should close');
  }

  // Availability

  Finder _availabilityStatusButton(UserAvailabilityStatus status) =>
      find.byWidgetPredicate(
        (widget) => widget is AvailabilityStatusButton && widget.type == status,
      );

  UserAvailabilityStatus _shownAvailabilityStatus() => tester
      .widget<AvailabilityStatusButton>(
        _availabilityStatusButton(UserAvailabilityStatus.online),
      )
      .current;

  Future<void> selectAvailabilityStatus(UserAvailabilityStatus status) async {
    await _waitForSettingsToBeApplied();

    final button = _availabilityStatusButton(status);
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);

    await tester.pumpUntil(
      () => _shownAvailabilityStatus() == status,
      timeout: _remoteChangeTimeout,
      reason: 'The availability status should change to ${status.name}',
    );
  }

  void verifyAvailabilityStatusIs(UserAvailabilityStatus status) {
    for (final other in UserAvailabilityStatus.values) {
      expect(
        tester
            .widget<AvailabilityButton>(
              find.descendant(
                of: _availabilityStatusButton(other),
                matching: find.byType(AvailabilityButton),
              ),
            )
            .isActive,
        other == status,
        reason:
            'Only the ${status.name} status button should be shown as active',
      );
    }

    final ringingDevice = find.byType(RingingDevice);
    if (!tester.any(ringingDevice)) return;

    final widget = tester.widget<RingingDevice>(ringingDevice);
    // A ringing device that went offline keeps the picker usable, so the user
    // can pick another.
    if (widget.isRingingDeviceOffline) return;

    expect(
      widget.shouldEntireWidgetBeDisabled,
      status == UserAvailabilityStatus.doNotDisturb ||
          status == UserAvailabilityStatus.offline,
      reason:
          'The ringing device picker should only be disabled while the user '
          'cannot be reached',
    );
  }

  Future<void> restoreAvailabilityStatus(UserAvailabilityStatus status) =>
      _restore('the availability status', () async {
        if (_availability.state.status == status) return;

        await _availability.changeAvailabilityStatus(
          status,
          _settings.state.availableDestinations,
        );
      });

  // Ringing device

  RingingDeviceType get currentRingingDevice => _user.ringingDevice;

  int get currentDestination => _user.settings.get(CallSetting.destination);

  /// A ringing device other than the current one that can actually ring,
  /// preferring a fixed destination since that never goes offline. Null when
  /// there is none, or when the current device has no button to return to.
  RingingDeviceType? get otherAvailableRingingDevice {
    final buttons = tester
        .widgetList<RingingDeviceButton>(find.byType(RingingDeviceButton))
        .toList();

    if (!buttons.any((button) => button.type == currentRingingDevice)) {
      return null;
    }

    final candidates = buttons
        .where(
          (button) => button.type != currentRingingDevice && button.canRing,
        )
        .map((button) => button.type);

    return candidates.contains(RingingDeviceType.fixed)
        ? RingingDeviceType.fixed
        : candidates.firstOrNull;
  }

  Finder _ringingDeviceButton(RingingDeviceType type) => find.byWidgetPredicate(
    (widget) => widget is RingingDeviceButton && widget.type == type,
  );

  Future<void> selectRingingDevice(RingingDeviceType type) async {
    await _waitForSettingsToBeApplied();

    final button = _ringingDeviceButton(type);
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);

    await tester.pumpUntil(
      () => currentRingingDevice == type,
      timeout: _remoteChangeTimeout,
      reason: 'The ringing device should change to ${type.name}',
    );
    await _waitForSettingsToBeApplied();
  }

  void verifyRingingDeviceIs(RingingDeviceType type) {
    expect(currentRingingDevice, type);
    expect(
      tester
          .widget<AvailabilityButton>(
            find.descendant(
              of: _ringingDeviceButton(type),
              matching: find.byType(AvailabilityButton),
            ),
          )
          .isActive,
      isTrue,
      reason: 'The ${type.name} ringing device button should be active',
    );
  }

  Future<void> restoreDestination(int destination) =>
      _restoreSetting(CallSetting.destination, destination);

  // Troubleshooting

  bool get isTroubleshootingUnlocked => _settings.state.showTroubleshooting;

  /// Tapping the build info ten times unlocks the troubleshooting settings,
  /// which also closes the about page.
  Future<void> unlockTroubleshootingThroughBuildInfo() async {
    final buildInfo = find.byType(BuildInfoTile);
    await tester.pumpUntilFound(
      buildInfo,
      reason: 'The build info should be shown on the about page',
    );

    for (var i = 0; i < 10; i++) {
      await tester.tap(buildInfo);
      await tester.pump(const Duration(milliseconds: 100));
    }

    await tester.pumpUntilGone(
      find.byType(AboutTheAppSubPage),
      reason: 'The about page should close once troubleshooting is unlocked',
    );
  }

  Future<void> verifyTroubleshootingIsUnlocked() async {
    await tester.pumpUntilFound(
      find.text(tester.msg.main.settings.troubleshootingUnlockedPopUp),
      reason: 'The user should be told troubleshooting was unlocked',
    );
    await tester.pumpUntil(
      () => isTroubleshootingUnlocked,
      reason: 'The troubleshooting settings should be unlocked',
    );
  }

  /// There is no way to lock troubleshooting again in the app itself.
  Future<void> restoreTroubleshootingUnlocked({required bool unlocked}) =>
      _restoreSetting(AppSetting.showTroubleshooting, unlocked);

  Future<void> openTroubleshootingPage() async {
    await _scrollIntoView(
      find.byType(TroubleshootingLinkTile),
      page: find.byType(AppPreferencesSubPage),
      reason: 'The troubleshooting link should be shown once unlocked',
    );
    await tester.tap(find.byType(TroubleshootingLinkTile));
    await tester.pumpUntilFound(
      find.byType(TroubleshootingSubPage),
      reason: 'The troubleshooting page should open',
    );
  }

  Future<void> closeTroubleshootingPage() =>
      _closePage(find.byType(TroubleshootingSubPage));

  void verifyEchoCancellationCalibrationIsShown() => expect(
    find.byType(EchoCancellationCalibrationTile),
    findsOneWidget,
    reason: 'Echo cancellation calibration should be offered while VoIP is on',
  );

  /// Calibration plays a tone and listens for its echo natively, without
  /// showing anything in the app, so all there is to do is give it time to
  /// finish before anything else uses the audio.
  Future<void> performEchoCancellationCalibration() async {
    await tester.tap(find.byType(EchoCancellationCalibrationTile));
    await tester.pumpFor(const Duration(seconds: 5));
  }

  // App preferences

  bool get isAllowedVoipCalling => _user.isAllowedVoipCalling;

  Finder _switchOf(Type tile) => find.descendant(
    of: find.byType(tile),
    matching: find.byType(StylizedSwitch),
  );

  bool _switchValue(Type tile) =>
      tester.widget<StylizedSwitch>(_switchOf(tile)).value;

  SettingKey<bool> _settingKeyOf(Type tile) => tester
      .widget<BoolSettingValue>(
        find.descendant(
          of: find.byType(tile),
          matching: find.byType(BoolSettingValue),
        ),
      )
      .settingKey;

  /// Turns VoIP off and on again, ending with it on whatever it started as,
  /// since the call tests that follow need it.
  Future<void> toggleUseVoipOffAndOn() async {
    await _scrollToPreference(UseVoipTile);

    try {
      if (_switchValue(UseVoipTile)) {
        await _toggle(UseVoipTile, to: false);
        expect(
          find.byType(UseMobileNumberAsFallbackTile),
          findsNothing,
          reason: 'Falling back to the mobile number only applies to VoIP',
        );
      }
      await _toggle(UseVoipTile, to: true);
      expect(_switchValue(UseVoipTile), isTrue);
    } finally {
      await _restoreSetting(CallSetting.useVoip, true);
    }
  }

  /// Toggles the switch of [tile] and back again. A switch the user has no
  /// permission to change is left alone.
  Future<void> togglePreferenceAndBack(Type tile) async {
    await _scrollToPreference(tile);

    if (tester.widget<StylizedSwitch>(_switchOf(tile)).onChanged == null) {
      debugPrint('Not toggling $tile: this user is not allowed to change it');
      return;
    }

    final original = _switchValue(tile);
    final key = _settingKeyOf(tile);

    try {
      await _toggle(tile, to: !original);
      await _toggle(tile, to: original);
    } finally {
      await _restoreSetting(key, original);
    }
  }

  Future<void> _toggle(Type tile, {required bool to}) async {
    await _waitForSettingsToBeApplied();
    await tester.tap(_switchOf(tile));
    await tester.pumpAndSettle();

    await _declineSendingLogsIfAsked();

    await tester.pumpUntil(
      () => _switchValue(tile) == to,
      timeout: _remoteChangeTimeout,
      reason: '$tile should be turned ${to ? 'on' : 'off'}',
    );
  }

  /// Turning remote logging on asks whether to send the logs saved so far.
  Future<void> _declineSendingLogsIfAsked() async {
    final dialogTitle = find.text(
      tester
          .msg
          .main
          .settings
          .list
          .debug
          .remoteLogging
          .sendToRemoteDialog
          .title,
    );
    if (!tester.any(dialogTitle)) return;

    await tester.tap(
      find.textIgnoringCase(tester.msg.generic.button.noThanks).last,
    );
    await tester.pumpUntilGone(
      dialogTitle,
      reason: 'The send logs dialog should close',
    );
  }

  Future<void> _scrollToPreference(Type tile) => _scrollIntoView(
    find.byType(tile),
    page: find.byType(AppPreferencesSubPage),
    reason: '$tile should be shown on the app preferences page',
  );

  /// Granting this opens a system dialog outside the app, which the test
  /// cannot answer, so it is only checked to be offered.
  Future<void> verifyIgnoreBatteryOptimizationsIsOffered() => _scrollIntoView(
    find.byType(IgnoreBatteryOptimizationsTile),
    page: find.byType(AppPreferencesSubPage),
    reason: 'Ignoring battery optimizations should be offered on Android',
  );

  // User page

  Future<void> verifyUsernameIs(String username) => _scrollIntoView(
    find.descendant(
      of: find.byType(UsernameTile),
      matching: find.textIgnoringCase(username),
    ),
    page: find.byType(UserSubPage),
    reason: 'The username the user logged in with should be shown',
  );

  String get currentMobileNumber =>
      _user.settings.get(CallSetting.mobileNumber);

  /// The current mobile number with its last digit changed, so it stays a
  /// valid number in the same country. Null when the current number can't be
  /// entered as is, since it then couldn't be put back.
  Future<String?> findAnotherValidMobileNumber() async {
    final original = currentMobileNumber;
    final validate = StrictlyValidateMobilePhoneNumber();

    // The dialog prefixes whatever is entered with a plus.
    if (!original.startsWith('+') || !await validate(original)) return null;

    final lastDigit = int.tryParse(original.substring(original.length - 1));
    if (lastDigit == null) return null;

    final prefix = original.substring(0, original.length - 1);
    for (var i = 1; i < 10; i++) {
      final candidate = '$prefix${(lastDigit + i) % 10}';
      if (await validate(candidate)) return candidate;
    }

    return null;
  }

  Future<void> changeMobileNumber(String number) async {
    await _waitForSettingsToBeApplied();
    await _scrollIntoView(
      find.byType(MobileNumberTile),
      page: find.byType(UserSubPage),
      reason: 'The mobile number should be shown on the user page',
    );
    await tester.tap(
      find.descendant(
        of: find.byType(MobileNumberTile),
        matching: find.byType(SettingTile),
      ),
    );

    final dialog = find.byType(EditMobileNumberDialog);
    await tester.pumpUntilFound(
      dialog,
      reason: 'The edit mobile number dialog should open',
    );
    await tester.enterText(
      find.descendant(of: dialog, matching: find.byType(TextFormField)),
      number,
    );
    await _saveDialog(dialog);

    await tester.pumpUntil(
      () => currentMobileNumber == number,
      timeout: _remoteChangeTimeout,
      reason: 'The mobile number should change to $number',
    );
    await _waitForSettingsToBeApplied();
  }

  void verifyMobileNumberIs(String number) => expect(
    find.descendant(
      of: find.byType(MobileNumberTile),
      matching: find.text(number),
    ),
    findsOneWidget,
    reason: 'The mobile number $number should be shown',
  );

  Future<void> restoreMobileNumber(String number) =>
      _restoreSetting(CallSetting.mobileNumber, number);

  bool get canChangeOutgoingNumber =>
      tester
          .widget<SettingTile>(
            find.descendant(
              of: find.byType(OutgoingNumberTile),
              matching: find.byType(SettingTile),
            ),
          )
          .onTap !=
      null;

  OutgoingNumber get currentOutgoingNumber =>
      _user.settings.get(CallSetting.outgoingNumber);

  List<OutgoingNumber> get _outgoingNumberOptions => [
    const OutgoingNumber.suppressed(),
    ..._user.client.outgoingNumbers,
  ];

  /// Another number the dialog offers, preferring a real number over
  /// suppressing it. Null when the current number isn't offered, as it then
  /// couldn't be picked again.
  OutgoingNumber? get otherOutgoingNumber {
    final current = currentOutgoingNumber;
    final options = _outgoingNumberOptions;

    if (!options.contains(current)) return null;

    final others = options.where((number) => number != current);
    return others.where((number) => !number.isSuppressed).firstOrNull ??
        others.firstOrNull;
  }

  Future<void> changeOutgoingNumber(OutgoingNumber number) async {
    await _waitForSettingsToBeApplied();
    await _scrollIntoView(
      find.byType(OutgoingNumberTile),
      page: find.byType(UserSubPage),
      reason: 'The outgoing number should be shown on the user page',
    );
    await tester.tap(
      find.descendant(
        of: find.byType(OutgoingNumberTile),
        matching: find.byType(SettingTile),
      ),
    );

    final dialog = find.byType(EditOutgoingNumberDialog);
    await tester.pumpUntilFound(
      dialog,
      reason: 'The edit outgoing number dialog should open',
    );
    await tester.tap(
      find.descendant(
        of: dialog,
        matching: find.byType(DropdownButtonFormField<OutgoingNumber>),
      ),
    );
    await tester.pumpAndSettle();

    // The open menu is built after the dialog, so its copy of the item comes
    // last.
    await tester.tap(
      find
          .byWidgetPredicate(
            (widget) =>
                widget is DropdownMenuItem<OutgoingNumber> &&
                widget.value == number,
          )
          .last,
    );
    await tester.pumpAndSettle();
    await _saveDialog(dialog);

    await tester.pumpUntil(
      () => currentOutgoingNumber == number,
      timeout: _remoteChangeTimeout,
      reason: 'The outgoing number should change to $number',
    );
    await _waitForSettingsToBeApplied();
  }

  void verifyOutgoingNumberIs(OutgoingNumber number) => expect(
    tester
        .widget<OutgoingNumberInfo>(
          find.descendant(
            of: find.byType(OutgoingNumberTile),
            matching: find.byType(OutgoingNumberInfo),
          ),
        )
        .item,
    number,
    reason: 'The outgoing number $number should be shown',
  );

  Future<void> restoreOutgoingNumber(OutgoingNumber number) =>
      _restoreSetting(CallSetting.outgoingNumber, number);

  Future<void> _saveDialog(Finder dialog) async {
    final save = find.descendant(
      of: dialog,
      matching: find.widgetWithText(
        TextButton,
        tester.msg.main.contacts.sharedContacts.form.saveContactButtonTitle,
      ),
    );

    // Saving is only enabled once the entered value has been validated.
    await tester.pumpUntil(
      () => tester.widget<TextButton>(save).onPressed != null,
      reason: 'Saving should be possible for a valid value',
    );
    await tester.tap(save);
    await tester.pumpUntilGone(dialog, reason: 'The dialog should close');
  }

  // Client page

  /// Opens the portal page behind [tile] in a web view and goes back again.
  /// Returns false when this user doesn't have the [tile].
  Future<bool> openPortalLinkAndReturn(Type tile) async {
    final link = find.byType(tile);
    final isShown = await _scrollIntoViewIfShown(
      link,
      page: find.byType(ClientSubPage),
    );
    if (!isShown) return false;

    await tester.tap(link);
    await _verifyWebViewOpensAndClose();
    return true;
  }

  /// Web pages load in the background, with a spinner shown meanwhile that
  /// would keep [WidgetTester.pumpAndSettle] from ever settling, so the
  /// content is not waited for.
  Future<void> _verifyWebViewOpensAndClose() async {
    final webView = find.byType(WebViewPage);
    await tester.pumpUntilFound(
      webView,
      reason: 'A web view should open',
      settle: false,
    );
    await tester.pumpFor(const Duration(seconds: 1));

    await tester.tap(
      find.descendant(of: webView, matching: find.byType(BackButton)),
    );
    await tester.pumpUntilGone(webView, reason: 'The web view should close');
  }

  bool get canChangeTemporaryRedirect =>
      tester.any(find.byType(TemporaryRedirectSettingTile));

  bool get hasTemporaryRedirect => _temporaryRedirects.state is Active;

  bool get hasTemporaryRedirectDestinations =>
      _temporaryRedirects.state.availableRedirectDestinations.isNotEmpty;

  Finder _settingsButton(String text) => find.byWidgetPredicate(
    (widget) => widget is SettingsButton && widget.text == text,
  );

  Future<void> startTemporaryRedirect() async {
    final actions = tester.msg.main.temporaryRedirect.actions;

    await tester.tap(_settingsButton(actions.setupRedirect.label));
    await tester.pumpUntilFound(
      find.byType(TemporaryRedirectPickerPage),
      reason: 'The temporary redirect picker should open',
    );

    await _pickLastRedirectDestination();
    await _confirmSuggestedRedirectEndDate();

    final start = _settingsButton(actions.startRedirect.label);
    await tester.pumpUntil(
      () => tester.widget<SettingsButton>(start).onPressed != null,
      reason: 'Starting the redirect should be possible',
    );
    await tester.tap(start);

    await tester.pumpUntilGone(
      find.byType(TemporaryRedirectPickerPage),
      reason: 'The picker should close once the redirect has started',
    );
    await tester.pumpUntil(
      () => hasTemporaryRedirect,
      reason: 'The temporary redirect should be active',
    );
  }

  Future<void> _pickLastRedirectDestination() async {
    final destination =
        _temporaryRedirects.state.availableRedirectDestinations.last;

    await tester.tap(
      find.byType(DropdownButton<TemporaryRedirectDestination>),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(destination.displayName).last);
    await tester.pumpAndSettle();
  }

  /// Goes through the date and time pickers, accepting the end date they
  /// suggest, an hour from now.
  Future<void> _confirmSuggestedRedirectEndDate() async {
    await tester.tap(
      find
          .descendant(of: find.byType(DateField), matching: find.byType(Field))
          .first,
    );
    await tester.pumpAndSettle();

    if (Platform.isIOS) {
      final picker = find.byType(CupertinoDatePicker);
      await tester.pumpUntilFound(
        picker,
        reason: 'The date picker should open',
      );
      // The popup is dismissed by tapping outside it, keeping the date as
      // long as its wheels aren't turned.
      await tester.tapAt(
        tester.getTopLeft(find.byType(TemporaryRedirectPickerPage)) +
            const Offset(20, 20),
      );
      await tester.pumpUntilGone(
        picker,
        reason: 'The date picker should close',
      );
    } else {
      await _confirmMaterialPicker(find.byType(DatePickerDialog));
      await _confirmMaterialPicker(find.byType(TimePickerDialog));
    }
  }

  Future<void> _confirmMaterialPicker(Finder picker) async {
    await tester.pumpUntilFound(picker, reason: '$picker should open');
    final ok = MaterialLocalizations.of(tester.element(picker)).okButtonLabel;
    await tester.tap(
      find.descendant(of: picker, matching: find.textIgnoringCase(ok)),
    );
    await tester.pumpUntilGone(picker, reason: '$picker should close');
  }

  void verifyTemporaryRedirectIsShown() {
    final actions = tester.msg.main.temporaryRedirect.actions;

    expect(
      _settingsButton(actions.stopRedirect.label),
      findsOneWidget,
      reason: 'An active redirect should be possible to stop',
    );
    expect(
      _settingsButton(actions.changeRedirect.label),
      findsOneWidget,
      reason: 'An active redirect should be possible to change',
    );
  }

  Future<void> stopTemporaryRedirect() async {
    final stop = _settingsButton(
      tester.msg.main.temporaryRedirect.actions.stopRedirect.label,
    );
    await tester.ensureVisible(stop);
    await tester.pumpAndSettle();
    await tester.tap(stop);

    await tester.pumpUntil(
      () => !hasTemporaryRedirect,
      reason: 'The temporary redirect should stop',
    );
  }

  void verifyNoTemporaryRedirectIsShown() => expect(
    _settingsButton(
      tester.msg.main.temporaryRedirect.actions.setupRedirect.label,
    ),
    findsOneWidget,
    reason: 'Without a redirect, setting one up should be offered',
  );

  Future<void> restoreNoTemporaryRedirect() =>
      _restore('the temporary redirect', () async {
        if (hasTemporaryRedirect) await CancelCurrentTemporaryRedirect()();
      });

  // About page

  void verifyAboutPageIsShown() {
    for (final tile in [FeatureAnnouncementTile, PrivacyPolicyTile]) {
      expect(
        find.byType(tile),
        findsOneWidget,
        reason: '$tile should be shown on the about page',
      );
    }
  }

  Future<void> verifyBuildInfoIsShown() => tester.pumpUntilFound(
    find.byType(BuildInfoTile),
    reason: 'The build info should be shown once it has been read',
  );

  Future<void> openFeatureAnnouncementsAndReturn() async {
    await tester.tap(find.byType(FeatureAnnouncementTile));
    await _verifyWebViewOpensAndClose();
  }

  // System page

  Future<void> viewLogs() async {
    final page = find.byType(LogSubPage);
    await _openSubPage(FontAwesomeIcons.scroll, page);

    expect(
      find.descendant(
        of: page,
        matching: find.text(
          tester
              .msg
              .main
              .settings
              .list
              .advancedSettings
              .troubleshooting
              .logs
              .title,
        ),
      ),
      findsOneWidget,
      reason: 'The logs page should be shown',
    );

    await _closePage(page);
  }

  Future<void> viewFeatureFlags() async {
    final page = find.byType(FeatureFlagsSubPage);
    await _openSubPage(FontAwesomeIcons.flag, page);

    expect(
      find.descendant(of: page, matching: find.byType(ListTile)),
      Feature.values.isEmpty ? findsNothing : findsWidgets,
      reason: 'Every feature flag should be listed',
    );

    await _closePage(page);
  }

  Future<void> viewVersionInfo() async {
    final page = find.byType(VersionInfoSubPage);
    await _openSubPage(FontAwesomeIcons.codeFork, page);

    expect(
      find.descendant(
        of: page,
        matching: find.text(vialerVersionInfo.flutter),
      ),
      findsOneWidget,
      reason: 'The Flutter version the app was built with should be shown',
    );

    await _closePage(page);
  }

  // Shared

  /// Each change to a remote setting blocks further changes until it's done,
  /// with the inputs ignoring taps meanwhile.
  Future<void> _waitForSettingsToBeApplied() => tester.pumpUntil(
    () => _settings.state.shouldAllowRemoteSettings,
    timeout: _remoteChangeTimeout,
    reason: 'Earlier setting changes should finish being applied',
  );

  Future<void> _scrollIntoView(
    Finder target, {
    required Finder page,
    required String reason,
  }) async {
    if (!await _scrollIntoViewIfShown(target, page: page)) {
      throw TestFailure(reason);
    }
  }

  /// Settings pages are lazily built lists, so a tile further down only
  /// exists once scrolled to. Starting from the top each time makes the
  /// order tiles are looked for in irrelevant.
  Future<bool> _scrollIntoViewIfShown(
    Finder target, {
    required Finder page,
  }) async {
    final position = tester
        .state<ScrollableState>(
          find.descendant(of: page, matching: find.byType(Scrollable)).first,
        )
        .position;

    position.jumpTo(position.minScrollExtent);
    await tester.pumpAndSettle();

    while (!tester.any(target)) {
      if (position.pixels >= position.maxScrollExtent) return false;

      position.jumpTo(
        (position.pixels + position.viewportDimension / 2).clamp(
          position.minScrollExtent,
          position.maxScrollExtent,
        ),
      );
      await tester.pumpAndSettle();
    }

    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    return true;
  }

  Future<void> _restoreSetting<T extends Object>(SettingKey<T> key, T value) =>
      _restore(key.toString(), () async {
        if (_user.settings.getOrNull(key) == value) return;
        await _settings.changeSetting(key, value);
      });

  /// Puts the account back the way the test found it, also after a failure,
  /// so the next run and the stages after this one aren't affected. It goes
  /// around the UI, which is in an unknown state when something failed, and
  /// never throws, which would hide the original failure.
  Future<void> _restore(
    String description,
    Future<void> Function() restore,
  ) async {
    try {
      await restore();
    } on Object catch (error) {
      debugPrint('Unable to restore $description: $error');
    }
  }
}

extension on RingingDeviceButton {
  /// Mirrors what the button itself checks before changing the destination.
  bool get canRing {
    final List<Destination?> candidates = switch (type) {
      RingingDeviceType.webphone => [
        destinations.findWebphoneAccountFor(user: user),
      ],
      RingingDeviceType.deskPhone ||
      RingingDeviceType.unknown => destinations.deskPhonesFor(user: user),
      RingingDeviceType.mobile => [destinations.findAppAccountFor(user: user)],
      RingingDeviceType.fixed => destinations.fixedDestinationsFor(user: user),
    };

    return candidates.nonNulls.any((destination) => destination.isOnline);
  }
}

extension on CommonFinders {
  /// Android shows some labels in capitals, iOS doesn't.
  Finder textIgnoringCase(String text) => byWidgetPredicate(
    (widget) =>
        widget is Text && widget.data?.toLowerCase() == text.toLowerCase(),
  );
}
