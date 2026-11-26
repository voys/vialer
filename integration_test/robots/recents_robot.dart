import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_platform_widgets/flutter_platform_widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vialer/data/models/call_records/call_record.dart';
import 'package:vialer/data/models/user/settings/app_setting.dart';
import 'package:vialer/data/models/user/user.dart';
import 'package:vialer/data/repositories/voipgrid/user_permissions.dart';
import 'package:vialer/dependency_locator.dart';
import 'package:vialer/domain/usecases/colltacts/shared_contacts/delete_shared_contact.dart';
import 'package:vialer/domain/usecases/colltacts/shared_contacts/get_shared_contacts.dart';
import 'package:vialer/domain/usecases/user/get_logged_in_user.dart';
import 'package:vialer/domain/util/call_record_extensions.dart';
import 'package:vialer/presentation/features/colltacts/controllers/shared_contacts/cubit.dart';
import 'package:vialer/presentation/features/colltacts/pages/add_shared_contact/page.dart';
import 'package:vialer/presentation/features/colltacts/widgets/details/widget.dart';
import 'package:vialer/presentation/features/colltacts/widgets/edit_shared_contact/page.dart';
import 'package:vialer/presentation/features/colltacts/widgets/shared_contact_form/util/field_row.dart';
import 'package:vialer/presentation/features/main_page.dart';
import 'package:vialer/presentation/features/recent/controllers/cubit.dart';
import 'package:vialer/presentation/features/recent/recent_calls_page.dart';
import 'package:vialer/presentation/features/recent/widgets/call_details_bottom_sheet.dart';
import 'package:vialer/presentation/features/recent/widgets/item.dart';
import 'package:vialer/presentation/features/recent/widgets/list.dart';
import 'package:vialer/presentation/features/recent/widgets/popup_menu.dart';
import 'package:vialer/presentation/features/settings/pages/app_preferences.dart';
import 'package:vialer/presentation/features/settings/widgets/tile/link/sub_page.dart';
import 'package:vialer/presentation/features/settings/widgets/tile/show_client_calls.dart';
import 'package:vialer/presentation/resources/messages.i18n.dart';
import 'package:vialer/presentation/shared/widgets/bottom_toggle.dart';
import 'package:vialer/presentation/shared/widgets/stylized_switch.dart';

import '../utils/test_extensions.dart';
import 'integration_test_robot.dart';

class RecentsRobot extends IntegrationTestRobot {
  RecentsRobot(super.tester);

  /// Every shared contact this robot adds starts with this, so ones left
  /// behind by an earlier run that failed can be recognised and removed.
  static const sharedContactNamePrefix = 'Recents integration test';

  /// Calls show up in the API a while after they end.
  static const _callHistoryTimeout = Duration(seconds: 90);
  static const _refreshInterval = Duration(seconds: 10);

  /// How many calls from the top a recent call may be, to allow for calls
  /// that the stages after it placed or received.
  static const _nearTopCount = 5;

  Future<void> navigateToRecentsTab() => tester.navigateToRecentsTab();

  void verifyIsOnHomeScreen() => ensureOnHomeScreen();

  Future<void> waitForCallsToLoad() => tester.pumpUntil(
    () =>
        tester.any(_list) &&
        _personalCallsState is! LoadingInitialRecentCalls &&
        _personalCallsState.callRecords.isNotEmpty,
    timeout: const Duration(seconds: 60),
    reason:
        'The recent calls should load, the test account is expected to have '
        'call history',
  );

  void verifyCallsAreShown() {
    expect(
      find.byType(RecentCallItem),
      findsWidgets,
      reason: 'The loaded calls should be shown in the list',
    );
  }

  /// Refreshes the list until the call shows up, as the API can take a while
  /// to list a call that just ended.
  Future<void> verifyOutgoingCallIsNearTheTop(
    String number, {
    required DateTime placedAfter,
  }) => _refreshUntil(
    () => _personalCallsState.callRecords
        .take(_nearTopCount)
        .any(
          (call) =>
              call.isOutbound &&
              call.date.isAfter(placedAfter) &&
              _isSameNumber(call.thirdPartyNumber, number),
        ),
    reason:
        'The outgoing call to $number placed after $placedAfter should be '
        'among the top $_nearTopCount recent calls',
  );

  /// The same refresh a pull-to-refresh performs, which works regardless of
  /// how far the list is scrolled.
  Future<void> refreshCalls() async {
    unawaited(
      tester
          .state<RefreshIndicatorState>(
            find
                .descendant(
                  of: _list.first,
                  matching: find.byType(RefreshIndicator),
                )
                .first,
          )
          .show(),
    );
    await tester.pumpAndSettle();
  }

  CallRecord get topCall => tester
      .widget<RecentCallItem>(find.byType(RecentCallItem).first)
      .callRecord;

  CallRecord? outgoingCallTo(String number) => _shownCalls.firstWhereOrNull(
    (call) => call.isOutbound && _isSameNumber(call.thirdPartyNumber, number),
  );

  /// A call that can be added as a shared contact: one without a contact,
  /// and to or from an outside number that the shared contact form accepts.
  /// [preferredNumber] is picked when shown, so the contact is for a number
  /// that belongs to the test setup.
  CallRecord? callToAddAsSharedContact({String? preferredNumber}) {
    final candidates = _shownCalls.where(
      (call) =>
          call.thirdPartyContact == null &&
          !call.isAnonymous &&
          call.callType == CallType.outside &&
          call.thirdPartyNumber.startsWith('+'),
    );

    return candidates.firstWhereOrNull(
          (call) =>
              preferredNumber != null &&
              _isSameNumber(call.thirdPartyNumber, preferredNumber),
        ) ??
        candidates.firstOrNull;
  }

  Future<void> openCallMenuAndSelect(
    CallRecord call,
    RecentCallMenuAction action,
  ) async {
    final item = _item(call);
    await tester.ensureVisible(item);
    await tester.pumpAndSettle();

    await tester.tap(
      find.descendant(of: item, matching: find.byType(RecentItemPopupMenu)),
    );
    await tester.pumpAndSettle();

    final menuItem = _menuItem(action);
    expect(
      menuItem,
      findsOneWidget,
      reason: 'The menu of the call should offer ${action.name}',
    );
    await tester.tap(menuItem);
    await tester.pumpAndSettle();
  }

  Future<void> clearClipboard() =>
      Clipboard.setData(const ClipboardData(text: ''));

  void verifyNumberCopiedMessageIsShown() {
    expect(
      find.text(tester.msg.main.recent.snackBar.copied),
      findsOneWidget,
      reason: 'A message should confirm the number was copied',
    );
  }

  /// The app doesn't wait for the copy to finish, so allow it a moment.
  Future<void> verifyClipboardContains(String text) async {
    String? copied;
    for (var attempt = 0; attempt < 20; attempt++) {
      copied = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
      if (copied == text) return;
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(copied, text, reason: 'The number of the call should be copied');
  }

  Future<void> waitForSnackBarToDismiss() => tester.pumpUntilGone(
    find.byType(SnackBar),
    reason: 'The snack bar should dismiss on its own',
  );

  Future<void> verifyCallDetailsAreShownFor(CallRecord call) async {
    await tester.pumpUntilFound(
      _callDetails,
      reason: 'The call details should open',
    );

    final strings = tester.msg.main.recent.list.item.popupMenu.callDetails;
    for (final text in [
      strings.callWith(call.displayLabel),
      strings.callId(call.id),
    ]) {
      expect(
        find.descendant(of: _callDetails, matching: find.text(text)),
        findsOneWidget,
        reason: 'The call details should show "$text"',
      );
    }
  }

  /// Taps the barrier above the sheet, which never covers the top of the
  /// screen.
  Future<void> closeCallDetails() async {
    final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
    await tester.tapAt(Offset(screen.width / 2, screen.height * 0.1));
    await tester.pumpUntilGone(
      _callDetails,
      reason: 'The call details should close when tapping outside of them',
    );
  }

  bool get showsAnsweredCalls =>
      _personalCallsState.callRecords.any((call) => !call.wasMissed);

  bool get showsMissedCalls =>
      _personalCallsState.callRecords.any((call) => call.wasMissed);

  Future<void> turnOnMissedCallsOnly() async {
    _verifyMissedCallsOnlyIs(enabled: false);
    await _tapMissedCallsOnlyToggle();
    _verifyMissedCallsOnlyIs(enabled: true);
  }

  Future<void> turnOffMissedCallsOnly() async {
    _verifyMissedCallsOnlyIs(enabled: true);
    await _tapMissedCallsOnlyToggle();
    _verifyMissedCallsOnlyIs(enabled: false);
  }

  Future<void> verifyOnlyMissedCallsAreShown({
    required bool expectAnyCalls,
  }) async {
    await tester.pumpUntil(
      () =>
          _personalCallsState is RecentCallsLoaded &&
          _personalCallsState.callRecords.every((call) => call.wasMissed),
      reason: 'Only missed calls should be listed once the filter is on',
    );

    expect(
      tester
          .widgetList<RecentCallItem>(find.byType(RecentCallItem))
          .every((item) => item.callRecord.wasMissed),
      isTrue,
      reason: 'Every call shown should be a missed call',
    );

    if (expectAnyCalls) {
      expect(
        find.byType(RecentCallItem),
        findsWidgets,
        reason: 'The missed calls that were listed before should be shown',
      );
    }
  }

  Future<void> verifyAnsweredCallsAreShownAgain() => tester.pumpUntil(
    () => _personalCallsState is RecentCallsLoaded && showsAnsweredCalls,
    reason: 'Answered calls should be listed again once the filter is off',
  );

  bool get canSeeClientCalls =>
      GetLoggedInUserUseCase()().hasPermission(Permission.canSeeClientCalls);

  bool get showClientCallsSetting =>
      GetLoggedInUserUseCase()().settings.get(AppSetting.showClientCalls);

  /// Changes the setting through the settings tab, then returns to the
  /// recents tab.
  Future<void> setShowClientCalls({required bool enabled}) async {
    await tester.navigateToSettingsTab();
    await tester.tap(
      find.widgetWithText(
        SubPageLinkTile,
        tester.msg.main.settings.subPage.appPreferences.title,
      ),
    );
    await tester.pumpUntilFound(
      find.byType(AppPreferencesSubPage),
      reason: 'The app preferences should open',
    );

    final tile = find.byType(ShowClientCallsTile);
    await tester.scrollUntilVisible(
      tile,
      100,
      scrollable: find
          .descendant(
            of: find.byType(AppPreferencesSubPage),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.descendant(of: tile, matching: find.byType(StylizedSwitch)),
    );
    await tester.pumpUntil(
      () => showClientCallsSetting == enabled,
      reason: 'Show client calls should be turned ${enabled ? 'on' : 'off'}',
    );

    await tester.goBack();
    await navigateToRecentsTab();
  }

  void verifyCallTabsAreShown() {
    for (final label in [_strings.tabs.personal, _strings.tabs.all]) {
      expect(
        _tab(label),
        findsOneWidget,
        reason: 'The "$label" tab should be shown',
      );
    }
  }

  void verifyCallTabsAreHidden() {
    expect(
      find.descendant(
        of: find.byType(RecentCallsPage),
        matching: find.byType(TabBar),
      ),
      findsNothing,
      reason: 'Without client calls there should only be personal calls',
    );
  }

  Future<void> tapAllCallsTab() => _tapTab(_strings.tabs.all);

  Future<void> tapPersonalCallsTab() => _tapTab(_strings.tabs.personal);

  Future<void> verifyClientCallsAreShown() => tester.pumpUntilFound(
    _visibleItem((call) => call.isClientCall),
    timeout: const Duration(seconds: 60),
    reason: 'The calls of the whole client should be shown',
  );

  Future<void> verifyPersonalCallsAreShown() => tester.pumpUntilFound(
    _visibleItem((call) => !call.isClientCall),
    timeout: const Duration(seconds: 60),
    reason: 'The personal calls should be shown',
  );

  Future<void> verifySharedContactFormIsPrefilledWith(String number) async {
    await tester.pumpUntilFound(
      find.byType(AddSharedContactPage),
      reason: 'The add shared contact form should open',
    );

    final phoneNumberField = find.descendant(
      of: _sharedContactFieldRow(_formStrings.phoneNumberHintText),
      matching: find.byType(EditableText),
    );
    expect(
      tester.widget<EditableText>(phoneNumberField.first).controller.text,
      number,
      reason: 'The number of the call should be filled in',
    );
  }

  /// The last name is cleared, as it may be prefilled from the caller's name
  /// and would otherwise end up in the name shown.
  Future<void> enterSharedContactName(String name) async {
    await tester.enterText(
      _sharedContactTextField(_formStrings.firstNameHintText),
      name,
    );
    await tester.enterText(
      _sharedContactTextField(_formStrings.lastNameHintText),
      '',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
  }

  Future<void> saveSharedContact() async {
    final saveButton = find.descendant(
      of: find.byType(AddSharedContactPage),
      matching: find.text(_formStrings.saveContactButtonTitle),
    );
    await tester.ensureVisible(saveButton);
    await tester.pumpAndSettle();
    await tester.tap(saveButton);
    await tester.pump();

    await tester.pumpUntilGone(
      find.byType(AddSharedContactPage),
      reason:
          'The form should close once the shared contact is saved, check for '
          'an error message if it stayed open',
    );
  }

  Future<void> waitForCallToShowName(String name) => _refreshUntil(
    () => tester.any(_itemShowing(name)),
    reason: 'A call should show "$name" once its number is a shared contact',
  );

  CallRecord callShowingName(String name) =>
      tester.widget<RecentCallItem>(_itemShowing(name).first).callRecord;

  Future<void> verifyContactDetailsShowName(String name) =>
      tester.pumpUntilFound(
        find.descendant(
          of: find.byType(ColltactPageDetails),
          matching: find.text(name),
        ),
        reason: 'The details of the shared contact "$name" should open',
      );

  /// The edit button is text on iOS and an icon on Android.
  Future<void> tapEditContactButton() async {
    await tester.tap(
      find.descendant(
        of: find.byType(ColltactPageDetails),
        matching: Platform.isIOS
            ? find.text(tester.msg.main.contacts.edit)
            : find.byWidgetPredicate(
                (widget) =>
                    widget is FaIcon &&
                    widget.icon == FontAwesomeIcons.pen.data,
              ),
      ),
    );
    await tester.pumpUntilFound(
      find.byType(EditSharedContactPage),
      reason: 'The shared contact should open for editing',
    );
  }

  /// Deleting closes both the edit page and the details page.
  Future<void> deleteSharedContact() async {
    final deleteButton = find.descendant(
      of: find.byType(EditSharedContactPage),
      matching: find.text(_formStrings.deleteContactButtonTitle),
    );
    await tester.ensureVisible(deleteButton);
    await tester.pumpAndSettle();
    await tester.tap(deleteButton);

    final confirmDialog = find.byType(PlatformAlertDialog);
    await tester.pumpUntilFound(
      confirmDialog,
      reason: 'Deleting should be confirmed first',
    );
    await tester.tap(
      find.descendant(
        of: confirmDialog,
        matching: find.text(
          _formStrings.confirmationDialog.deleteContactButtonTitle,
        ),
      ),
    );
    await tester.pump();

    await tester.pumpUntilGone(
      find.byType(EditSharedContactPage),
      reason: 'The edit page should close once the contact is deleted',
    );
    await tester.pumpUntilGone(
      find.byType(ColltactPageDetails),
      reason: 'The contact details should close once the contact is deleted',
    );
  }

  Future<void> verifyNoCallShowsName(String name) => _refreshUntil(
    () => !tester.any(_itemShowing(name)),
    reason: 'No call should show "$name" once the shared contact is deleted',
  );

  /// Removes shared contacts added by this robot through the API, for when a
  /// test failed before deleting its contact through the app.
  Future<void> deleteLeftoverSharedContacts() async {
    final sharedContacts = await dependencyLocator<GetSharedContactsUseCase>()(
      forceSharedContactsRefresh: true,
    );
    final leftovers = sharedContacts.where(
      (contact) =>
          contact.givenName?.startsWith(sharedContactNamePrefix) ?? false,
    );
    if (leftovers.isEmpty) return;

    final delete = DeleteSharedContactUseCase();
    for (final contact in leftovers) {
      await delete(uuid: contact.id);
    }

    await tester
        .element(find.byType(MainPage, skipOffstage: false))
        .read<SharedContactsCubit>()
        .loadSharedContacts(fullRefresh: true);
  }

  RecentMainMessages get _strings => tester.msg.main.recent;

  FormSharedContactsContactsMainMessages get _formStrings =>
      tester.msg.main.contacts.sharedContacts.form;

  Finder get _list => find.byType(RecentCallsList);

  /// The personal calls cubit, even when the client calls tab is shown too:
  /// that one is provided under its own type.
  RecentCallsState get _personalCallsState =>
      tester.element(_list.first).read<RecentCallsCubit>().state;

  List<CallRecord> get _shownCalls => tester
      .widgetList<RecentCallItem>(find.byType(RecentCallItem))
      .map((item) => item.callRecord)
      .toList();

  Finder get _callDetails => find.byType(CallDetailsBottomSheet);

  Finder _item(CallRecord call) => find
      .byWidgetPredicate(
        (widget) => widget is RecentCallItem && widget.callRecord.id == call.id,
      )
      .first;

  Finder _visibleItem(bool Function(CallRecord) matches) => find
      .byWidgetPredicate(
        (widget) => widget is RecentCallItem && matches(widget.callRecord),
      )
      .hitTestable();

  Finder _itemShowing(String name) => find.ancestor(
    of: find.text(name),
    matching: find.byType(RecentCallItem),
  );

  Finder _menuItem(RecentCallMenuAction action) => find.byWidgetPredicate(
    (widget) =>
        widget is PopupMenuItem<RecentCallMenuAction> &&
        widget.value == action &&
        widget.enabled,
  );

  Finder get _missedCallsOnlySwitch => find.descendant(
    of: find.byWidgetPredicate(
      (widget) =>
          widget is BottomToggle && widget.name == _strings.onlyShowMissedCalls,
    ),
    matching: find.byType(StylizedSwitch),
  );

  Future<void> _tapMissedCallsOnlyToggle() async {
    await tester.tap(_missedCallsOnlySwitch);
    await tester.pumpAndSettle();
  }

  void _verifyMissedCallsOnlyIs({required bool enabled}) {
    expect(
      tester.widget<StylizedSwitch>(_missedCallsOnlySwitch).value,
      enabled,
      reason: 'Missed calls only should be ${enabled ? 'on' : 'off'}',
    );
  }

  /// The tab labels are shown in capitals.
  Finder _tab(String label) => find.descendant(
    of: find.descendant(
      of: find.byType(RecentCallsPage),
      matching: find.byType(TabBar),
    ),
    matching: find.text(label.toUpperCase()),
  );

  Future<void> _tapTab(String label) async {
    await tester.tap(_tab(label));
    await tester.pumpAndSettle();
  }

  Finder _sharedContactFieldRow(String hintText) => find.byWidgetPredicate(
    (widget) => widget is SharedContactFieldRow && widget.hintText == hintText,
  );

  Finder _sharedContactTextField(String hintText) => find.descendant(
    of: _sharedContactFieldRow(hintText),
    matching: find.byType(TextFormField),
  );

  Future<void> _refreshUntil(
    bool Function() condition, {
    required String reason,
  }) async {
    var waited = Duration.zero;
    while (!condition()) {
      if (waited >= _callHistoryTimeout) {
        throw TestFailure('$reason (waited $_callHistoryTimeout)');
      }
      if (waited > Duration.zero) await tester.pumpFor(_refreshInterval);
      await refreshCalls();
      waited += _refreshInterval;
    }
  }
}

/// Numbers can be listed with or without the country code, so only the
/// subscriber part is compared.
bool _isSameNumber(String a, String b) {
  String subscriberPart(String number) {
    final digits = number.replaceAll(RegExp(r'\D'), '');
    return digits.length > 9 ? digits.substring(digits.length - 9) : digits;
  }

  return subscriberPart(a) == subscriberPart(b);
}

extension<T> on Iterable<T> {
  T? firstWhereOrNull(bool Function(T) test) {
    for (final element in this) {
      if (test(element)) return element;
    }
    return null;
  }
}
