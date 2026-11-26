import 'dart:io' show Platform;

import 'package:collection/collection.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_contacts/flutter_contacts.dart' as device;
import 'package:flutter_platform_widgets/flutter_platform_widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:material_ui/material_ui.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:vialer/data/models/colltacts/colltact.dart';
import 'package:vialer/data/models/colltacts/colltact_tab.dart';
import 'package:vialer/data/models/colltacts/contact.dart';
import 'package:vialer/data/models/colltacts/shared_contacts/shared_contact.dart';
import 'package:vialer/data/models/relations/colleagues/colleague.dart';
import 'package:vialer/dependency_locator.dart';
import 'package:vialer/domain/usecases/colltacts/shared_contacts/delete_shared_contact.dart';
import 'package:vialer/domain/usecases/colltacts/shared_contacts/get_shared_contacts.dart';
import 'package:vialer/presentation/features/colltacts/controllers/colleagues/cubit.dart';
import 'package:vialer/presentation/features/colltacts/controllers/contacts/cubit.dart';
import 'package:vialer/presentation/features/colltacts/controllers/cubit.dart';
import 'package:vialer/presentation/features/colltacts/controllers/shared_contacts/cubit.dart';
import 'package:vialer/presentation/features/colltacts/pages/add_shared_contact/page.dart';
import 'package:vialer/presentation/features/colltacts/pages/colltacts_page.dart';
import 'package:vialer/presentation/features/colltacts/widgets/colltact_list/avatar.dart';
import 'package:vialer/presentation/features/colltacts/widgets/colltact_list/colltact_item_list.dart';
import 'package:vialer/presentation/features/colltacts/widgets/colltact_list/colltacts_tab_bar.dart';
import 'package:vialer/presentation/features/colltacts/widgets/colltact_list/details/widget.dart';
import 'package:vialer/presentation/features/colltacts/widgets/colltact_list/item.dart';
import 'package:vialer/presentation/features/colltacts/widgets/colltact_list/search.dart';
import 'package:vialer/presentation/features/colltacts/widgets/colltact_list/util/kind.dart';
import 'package:vialer/presentation/features/colltacts/widgets/colltact_list/widget.dart';
import 'package:vialer/presentation/features/colltacts/widgets/details/widget.dart';
import 'package:vialer/presentation/features/colltacts/widgets/edit_shared_contact/page.dart';
import 'package:vialer/presentation/features/colltacts/widgets/shared_contact_form/util/field_row.dart';
import 'package:vialer/presentation/features/colltacts/widgets/shared_contact_form/widget.dart';
import 'package:vialer/presentation/features/settings/widgets/settings_button.dart';
import 'package:vialer/presentation/resources/messages.i18n.dart';
import 'package:vialer/presentation/shared/widgets/bottom_toggle.dart';
import 'package:vialer/presentation/shared/widgets/stylized_switch.dart';

import '../utils/test_extensions.dart';
import '../utils/test_log.dart';
import 'integration_test_robot.dart';

class ContactsRobot extends IntegrationTestRobot {
  ContactsRobot(super.tester);

  /// Colleagues arrive over the websocket, which can take a while to connect.
  static const _listsLoadTimeout = Duration(seconds: 60);

  BuildContext get _context => tester.element(
    find.byType(ColltactsPage, skipOffstage: false).first,
  );

  ContactsCubit get _contactsCubit => _context.read<ContactsCubit>();

  ColleaguesCubit get _colleaguesCubit => _context.read<ColleaguesCubit>();

  SharedContactsCubit get _sharedContactsCubit =>
      _context.read<SharedContactsCubit>();

  List<ColltactTab> get _tabs => _context.read<ColltactsTabsCubit>().state;

  FormSharedContactsContactsMainMessages get _form =>
      tester.msg.main.contacts.sharedContacts.form;

  /// Waiting on the state rather than the screen, because the loading
  /// indicators animate forever and would keep `pumpAndSettle` from returning.
  Future<void> waitForListsToLoad() => tester.pumpUntil(
    () =>
        _contactsCubit.state is ContactsLoaded &&
        _sharedContactsCubit.state is SharedContactsLoaded &&
        _colleaguesCubit.state is ColleaguesLoaded,
    timeout: _listsLoadTimeout,
    reason:
        'Phone contacts, shared contacts and colleagues should all load. '
        'Colleagues come in over the websocket, so check that it connects.',
  );

  void verifyContactsListIsShown() {
    ensureOnHomeScreen();
    expect(
      find.byType(ColltactDetails),
      findsNothing,
      reason: 'No contact details should be left open',
    );
    expect(
      _searchText,
      isEmpty,
      reason: 'The contacts search should be left empty',
    );
  }

  // Tabs

  ColltactTab get selectedTab => _tabs[_tabController.index];

  TabController get _tabController => tester
      .widget<TabBar>(
        find.descendant(
          of: find.byType(ColltactsTabBar),
          matching: find.byType(TabBar),
        ),
      )
      .controller!;

  Future<void> openTab(ColltactTab tab) async {
    expect(
      _tabs,
      contains(tab),
      reason:
          'The $tab tab should be shown. The colleagues tab only shows when '
          'the user may view colleagues and has at least one.',
    );

    await tester.tap(
      find.descendant(
        of: find.byType(ColltactsTabBar),
        matching: find.text(_tabTitle(tab).toUpperCase()),
      ),
    );
    await tester.pumpAndSettle();
  }

  void verifyTabIsSelected(ColltactTab tab) {
    expect(selectedTab, tab, reason: 'The $tab tab should be selected');
    expect(
      _tabContent(tab),
      findsOneWidget,
      reason: 'The list for the $tab tab should be shown',
    );
  }

  String _tabTitle(ColltactTab tab) {
    final titles = tester.msg.main.contacts.tabBar;

    return switch (tab) {
      ColltactTab.contacts => titles.contactsTabTitle,
      ColltactTab.sharedContact => titles.sharedTabTitle,
      ColltactTab.colleagues => titles.colleaguesTabTitle,
    };
  }

  Finder _tabContent(ColltactTab tab) => switch (tab) {
    ColltactTab.contacts => find.byWidgetPredicate(
      (widget) =>
          widget is ColltactItemList && widget.kind == ColltactKind.contact,
    ),
    ColltactTab.sharedContact => find.byType(SharedContactItemList),
    ColltactTab.colleagues => find.byType(ColleagueItemList),
  };

  // Search

  Finder get _searchField => find.descendant(
    of: find.byType(SearchTextField),
    matching: find.byType(TextField),
  );

  String get _searchText =>
      tester.widget<TextField>(_searchField).controller?.text ?? '';

  Future<void> search(String term) async {
    await tester.enterText(_searchField, term);
    await tester.pumpAndSettle();
    await tester._hideKeyboard();
  }

  Future<void> clearSearch() async {
    final clearButton = find.descendant(
      of: find.byType(SearchTextField),
      matching: find.byType(IconButton),
    );

    if (tester.any(clearButton)) {
      await tester.tap(clearButton);
      await tester.pumpAndSettle();
    }

    expect(_searchText, isEmpty, reason: 'The search should be cleared');
  }

  // List

  /// List items render their name as rich text, to highlight the search term.
  Finder _listItem(String name) => find.ancestor(
    of: find.descendant(
      of: _tabContent(selectedTab),
      matching: find.text(name, findRichText: true),
    ),
    matching: find.byType(ColltactItem),
  );

  Future<void> waitForListToShow(String name) => tester.pumpUntilFound(
    _listItem(name),
    reason: '"$name" should be listed in the ${selectedTab.name} tab',
  );

  Future<void> waitForListToNotShow(String name) => tester.pumpUntilGone(
    _listItem(name),
    reason: '"$name" should not be listed in the ${selectedTab.name} tab',
  );

  Future<void> openDetails(String name) async {
    await tester.tap(_listItem(name).first);
    await tester.pumpAndSettle();

    await tester.pumpUntilFound(
      find.byType(ColltactDetails),
      reason: 'Tapping "$name" should open their details',
    );
  }

  // Details

  Finder _inDetails(Finder finder) =>
      find.descendant(of: find.byType(ColltactDetails), matching: finder);

  Finder _detailsPhoneNumber(String number) => _inDetails(
    find.byWidgetPredicate(
      (widget) =>
          widget is Text &&
          widget.data != null &&
          widget.data!._isSamePhoneNumberAs(number),
    ),
  );

  void verifyDetailsShowName(String name) => expect(
    _inDetails(find.text(name)),
    findsOneWidget,
    reason: 'The details should show the name "$name"',
  );

  Future<void> waitForDetailsToShowName(String name) => tester.pumpUntilFound(
    _inDetails(find.text(name)),
    reason: 'The details should show the name "$name"',
  );

  void verifyDetailsShowPhoneNumber(String number) => expect(
    _detailsPhoneNumber(number),
    findsWidgets,
    reason: 'The details should show the phone number $number',
  );

  Future<void> tapPhoneNumberInDetails(String number) async {
    await tester.tap(
      find
          .ancestor(
            of: _detailsPhoneNumber(number),
            matching: find.byType(ListTile),
          )
          .first,
    );
    await tester.pump();
  }

  // Colleagues

  List<Colleague> get colleagues => switch (_colleaguesCubit.state) {
    final ColleaguesLoaded state => state.colleagues,
    LoadingColleagues() => const [],
  };

  void verifyColleaguesAreListed() {
    expect(
      colleagues,
      isNotEmpty,
      reason: 'The test account should have colleagues',
    );
    expect(
      find.descendant(
        of: _tabContent(ColltactTab.colleagues),
        matching: find.byType(ColltactItem),
      ),
      findsWidgets,
      reason: 'Colleagues should be listed',
    );
  }

  /// The availability shows as the avatar's colour and icon.
  void verifyDetailsShowAvailabilityOf(String colleagueId) {
    final colleague = colleagues.firstWhere((c) => c.id == colleagueId);
    final avatar = tester.widget<UserAvatar>(
      _inDetails(find.byType(UserAvatar)),
    );

    expect(
      avatar.status,
      colleague._shownAvailability,
      reason: "The details should show ${colleague.name}'s availability",
    );
    expect(
      avatar.relevantContext,
      colleague.mostRelevantContext,
      reason: 'The details should show whether ${colleague.name} is in a call',
    );
  }

  Finder get _onlineColleaguesOnlySwitch => find.descendant(
    of: find.byType(BottomToggle),
    matching: find.byType(StylizedSwitch),
  );

  bool get showsOnlineColleaguesOnly =>
      tester.widget<StylizedSwitch>(_onlineColleaguesOnlySwitch).value;

  Future<void> setShowOnlineColleaguesOnly(bool value) async {
    if (showsOnlineColleaguesOnly != value) {
      await tester.tap(_onlineColleaguesOnlySwitch);
      await tester.pumpAndSettle();
    }

    expect(
      _colleaguesCubit.state.showOnlineColleaguesOnly,
      value,
      reason: 'Only online colleagues should ${value ? '' : 'no longer '}show',
    );
  }

  /// For when a test failed partway, so the toggle on screen can't be relied
  /// on.
  void restoreShowOnlineColleaguesOnly(bool value) {
    if (_colleaguesCubit.state.showOnlineColleaguesOnly != value) {
      _colleaguesCubit.showOnlineColleaguesOnly = value;
    }
  }

  // Shared contacts

  List<SharedContact> get _sharedContacts =>
      switch (_sharedContactsCubit.state) {
        final SharedContactsLoaded state => state.sharedContacts,
        _ => const [],
      };

  /// The button is in the list header, or in the placeholder when there are no
  /// shared contacts yet.
  Future<void> tapAddSharedContactButton() async {
    await tester.tap(
      find
          .descendant(
            of: find.byType(SharedContactItemList),
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is SettingsButton &&
                  widget.icon == FontAwesomeIcons.userPlus,
            ),
          )
          .hitTestable()
          .first,
    );
    await tester.pumpAndSettle();

    await tester.pumpUntilFound(
      find.byType(AddSharedContactPage),
      reason: 'The add shared contact form should open',
    );
  }

  Future<void> fillInSharedContactForm({
    required String givenName,
    required String familyName,
    required String phoneNumber,
  }) async {
    await _enterInFormField(_form.firstNameHintText, givenName);
    await _enterInFormField(_form.lastNameHintText, familyName);
    await _enterPhoneNumber(phoneNumber);
  }

  Future<void> changeSharedContactFamilyName(String familyName) =>
      _enterInFormField(_form.lastNameHintText, familyName);

  Finder _formField(String hintText) => find.descendant(
    of: find.byWidgetPredicate(
      (widget) =>
          widget is SharedContactFieldRow && widget.hintText == hintText,
    ),
    matching: find.byType(TextFormField),
  );

  Future<void> _enterInFormField(String hintText, String text) async {
    await tester.enterText(_formField(hintText).first, text);
    await tester.pumpAndSettle();
  }

  /// A new form fills in the country code once it has looked it up, which
  /// would overwrite a number entered before then.
  Future<void> _enterPhoneNumber(String number) async {
    final field = _formField(_form.phoneNumberHintText).first;

    await tester.pumpUntil(
      () =>
          tester.widget<TextFormField>(field).controller?.text.isNotEmpty ??
          false,
      reason: 'The phone number field should be filled with a country code',
    );

    await tester.enterText(field, number);
    await tester.pumpAndSettle();
  }

  Finder _formButton(String title) => find
      .ancestor(
        of: find.descendant(
          of: find.byType(SharedContactForm),
          matching: _textIgnoringCase(title),
        ),
        matching: find.byType(OutlinedButton),
      )
      .first;

  Future<void> saveSharedContactForm() async {
    await tester._hideKeyboard();

    final saveButton = _formButton(_form.saveContactButtonTitle);
    await tester.ensureVisible(saveButton);
    await tester.pumpAndSettle();
    await tester.tap(saveButton);
    await tester.pump();

    await tester.pumpUntilGone(
      find.byType(SharedContactForm),
      reason:
          'Saving should close the shared contact form. If it is still open, '
          'either a field was rejected (the phone number needs a country '
          'code) or saving failed and an error was shown.',
    );
  }

  Future<void> waitForSharedContact(String displayName) => tester.pumpUntil(
    () => _sharedContacts.any((contact) => contact.displayName == displayName),
    reason: 'The shared contact "$displayName" should have been saved',
  );

  Future<void> waitForSharedContactToBeDeleted(String displayName) =>
      tester.pumpUntil(
        () => _sharedContacts.none(
          (contact) => contact.displayName == displayName,
        ),
        reason: 'The shared contact "$displayName" should have been deleted',
      );

  /// The edit button is text on iOS and an icon on Android.
  Future<void> tapEditButton() async {
    await tester.tap(
      _inDetails(
        Platform.isIOS
            ? find.text(tester.msg.main.contacts.edit)
            : find.byIcon(FontAwesomeIcons.pen.data),
      ),
    );
    await tester.pumpAndSettle();

    await tester.pumpUntilFound(
      find.byType(EditSharedContactPage),
      reason: 'The edit shared contact form should open',
    );
  }

  /// Deleting closes both the form and the details behind it.
  Future<void> deleteSharedContact() async {
    final deleteButton = _formButton(_form.deleteContactButtonTitle);
    await tester.ensureVisible(deleteButton);
    await tester.pumpAndSettle();
    await tester.tap(deleteButton);
    await tester.pumpAndSettle();

    final dialog = find.byType(PlatformAlertDialog);
    await tester.pumpUntilFound(
      dialog,
      reason: 'Deleting should ask for confirmation',
    );

    await tester.tap(
      find.descendant(
        of: dialog,
        matching: _textIgnoringCase(
          _form.confirmationDialog.deleteContactButtonTitle,
        ),
      ),
    );
    await tester.pump();

    await tester.pumpUntil(
      () =>
          !tester.any(find.byType(SharedContactForm)) &&
          !tester.any(find.byType(ColltactPageDetails)),
      reason: "Deleting should close the form and the contact's details",
    );
  }

  /// Goes through the API rather than the screen, so it also works when a
  /// test failed partway.
  Future<void> deleteSharedContactsWithGivenName(String givenName) async {
    final sharedContacts = await dependencyLocator<GetSharedContactsUseCase>()(
      forceSharedContactsRefresh: true,
    );
    final deleteSharedContact = DeleteSharedContactUseCase();

    for (final contact in sharedContacts) {
      if (contact.givenName != givenName) continue;

      TestLog.step(
        '🧹',
        'Deleting leftover shared contact "${contact.displayName}"',
      );
      await deleteSharedContact(uuid: contact.id);
    }

    await _sharedContactsCubit.loadSharedContacts(fullRefresh: true);
  }

  // Phone contacts

  List<Contact> get phoneContacts => switch (_contactsCubit.state) {
    final ContactsLoaded state => state.contacts.toList(),
    _ => const [],
  };

  void verifyPhoneContactsTabShowsContactsOrEmptyState() {
    final state = _contactsCubit.state;

    expect(
      state,
      isA<ContactsLoaded>(),
      reason: 'Phone contacts should have loaded',
    );
    expect(
      (state as ContactsLoaded).noContactPermission,
      isFalse,
      reason:
          'The app should have the contacts permission: the runner grants it '
          'on Android and it is mocked on iOS',
    );

    final tabContent = _tabContent(ColltactTab.contacts);

    if (state.contacts.isEmpty) {
      expect(
        find.descendant(
          of: tabContent,
          matching: find.text(tester.msg.main.contacts.list.empty.title),
        ),
        findsOneWidget,
        reason: 'Without phone contacts, the empty state should be shown',
      );
    } else {
      expect(
        find.descendant(of: tabContent, matching: find.byType(ColltactItem)),
        findsWidgets,
        reason: 'The phone contacts should be listed',
      );
    }
  }

  /// Android only: on iOS the contacts permission is only mocked, so writing
  /// to the address book would prompt for real access.
  Future<void> addDeviceContact({
    required String givenName,
    required String familyName,
    required String phoneNumber,
  }) async {
    // Writing without the permission crashes the app, rather than failing.
    final canWrite = await Permission.contacts.status.isGranted;
    if (!canWrite) {
      throw TestFailure(
        'The app needs WRITE_CONTACTS to add a contact to the device. The '
        'runner should install the app with all its permissions granted.',
      );
    }

    await device.FlutterContacts.insertContact(
      device.Contact(
        name: device.Name(first: givenName, last: familyName),
        phones: [device.Phone(phoneNumber)],
      ),
    );
  }

  Future<void> deleteDeviceContactsWithGivenName(String givenName) async {
    for (final contact in await device.FlutterContacts.getContacts()) {
      if (!contact.displayName.startsWith('$givenName ')) continue;

      TestLog.step('🧹', 'Deleting device contact "${contact.displayName}"');
      await device.FlutterContacts.deleteContact(contact);
    }
  }

  /// Returns the name the app shows for the phone contact.
  Future<String> waitForPhoneContactNamedWith(String text) async {
    await _reloadPhoneContactsUntil(
      () => _phoneContactNamedWith(text) != null,
      reason: 'A phone contact named with "$text" should be imported',
    );

    return Colltact.contact(_phoneContactNamedWith(text)!).name;
  }

  Future<void> waitForPhoneContactToBeRemoved(String text) =>
      _reloadPhoneContactsUntil(
        () => _phoneContactNamedWith(text) == null,
        reason: 'The phone contact named with "$text" should be gone',
      );

  Contact? _phoneContactNamedWith(String text) =>
      phoneContacts.firstWhereOrNull(
        (contact) => Colltact.contact(contact).name.contains(text),
      );

  /// A reload returns the cached contacts while the import from the device
  /// runs in the background, so a change can take more than one reload.
  Future<void> _reloadPhoneContactsUntil(
    bool Function() condition, {
    required String reason,
  }) async {
    for (var attempt = 0; attempt < 15; attempt++) {
      await _contactsCubit.reloadContacts();
      await tester.pump(const Duration(seconds: 1));

      if (condition()) {
        await tester.pumpAndSettle();
        return;
      }
    }

    throw TestFailure(reason);
  }
}

/// Buttons built with [PlatformText] are upper case on Android.
Finder _textIgnoringCase(String text) => find.byWidgetPredicate(
  (widget) =>
      widget is Text && widget.data?.toLowerCase() == text.toLowerCase(),
);

extension on WidgetTester {
  Future<void> _hideKeyboard() async {
    FocusManager.instance.primaryFocus?.unfocus();
    await pumpAndSettle();
  }
}

extension on String {
  /// Compares the last digits only, so the same number with or without a
  /// country code, or formatted differently, still matches.
  bool _isSamePhoneNumberAs(String other) {
    String significantDigits(String number) {
      final digits = number.replaceAll(RegExp(r'\D'), '');
      return digits.length > 9 ? digits.substring(digits.length - 9) : digits;
    }

    final digits = significantDigits(this);
    return digits.isNotEmpty && digits == significantDigits(other);
  }
}

extension on Colleague {
  /// The availability the avatar shows, which treats a colleague reachable on
  /// the app or a fixed number as available.
  ColleagueAvailabilityStatus? get _shownAvailability => map(
    (colleague) => colleague.isAvailableOnMobileAppOrFixedDestination
        ? ColleagueAvailabilityStatus.available
        : colleague.status,
    unconnectedVoipAccount: (_) => ColleagueAvailabilityStatus.unknown,
  );
}
