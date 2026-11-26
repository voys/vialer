import 'dart:io' show Platform;

import 'package:collection/collection.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vialer/data/models/colltacts/colltact_tab.dart';
import 'package:vialer/data/models/colltacts/shared_contacts/shared_contact.dart';
import 'package:vialer/data/models/relations/colleagues/colleague.dart';

import '../robots/calling_robot.dart';
import '../robots/contacts_robot.dart';
import '../utils/test_env.dart';
import '../utils/test_extensions.dart';
import '../utils/test_log.dart';

/// Every contact these tests create has this given name, so any left behind
/// by an earlier run that failed can be recognised and removed.
const _testContactGivenName = 'IntegrationTest';

Future<void> runContactsTests(IntegrationTestContext context) async {
  final tester = context.tester;

  TestLog.group('👥', 'Contacts');

  await tester.navigateToContactsTab();

  final robot = ContactsRobot(tester);

  // Created while still on the home screen, which it checks for. Creating it
  // also stops prompts from interrupting the call.
  final callingRobot = context.config.canPlaceRealCalls
      ? CallingRobot(tester, context.config)
      : null;

  await robot.waitForListsToLoad();
  final initialTab = robot.selectedTab;

  await TestLog.test(
    'User can switch between tabs',
    () => _userCanSwitchBetweenTabs(robot),
  );
  await TestLog.test(
    'User can browse colleagues',
    () => _userCanBrowseColleagues(robot),
  );
  await TestLog.test(
    'User can manage a shared contact',
    () => _userCanManageASharedContact(robot, callingRobot),
  );
  await TestLog.test(
    'User can see phone contacts',
    () => _userCanSeePhoneContacts(robot),
  );

  // The selected tab is remembered, so leave it as it was found.
  await robot.openTab(initialTab);
  robot.verifyContactsListIsShown();
}

Future<void> _userCanSwitchBetweenTabs(ContactsRobot robot) async {
  for (final tab in [
    ColltactTab.contacts,
    ColltactTab.sharedContact,
    ColltactTab.colleagues,
    ColltactTab.contacts,
  ]) {
    TestLog.step('🗂️', 'Opening the ${tab.name} tab');
    await robot.openTab(tab);
    robot.verifyTabIsSelected(tab);
  }
}

Future<void> _userCanBrowseColleagues(ContactsRobot robot) async {
  await robot.openTab(ColltactTab.colleagues);

  final showedOnlineColleaguesOnly = robot.showsOnlineColleaguesOnly;

  try {
    // Only online colleagues show by default, and all of the test account's
    // colleagues may well be offline.
    await robot.setShowOnlineColleaguesOnly(false);
    robot.verifyColleaguesAreListed();

    final colleague =
        robot.colleagues.firstWhereOrNull(
          (colleague) => colleague._hasName && colleague.number != null,
        ) ??
        robot.colleagues.firstWhere((colleague) => colleague._hasName);

    TestLog.detail('Colleagues listed', robot.colleagues.length);
    TestLog.detail('Colleague', colleague.name);
    TestLog.detail("Colleague's number", colleague.number);

    await _userCanSearchColleagues(robot, colleague);
    await _userCanSeeAColleaguesDetails(robot, colleague);
    await robot.clearSearch();

    await _userCanHideOfflineColleagues(robot);

    await robot.setShowOnlineColleaguesOnly(showedOnlineColleaguesOnly);
  } finally {
    await _withoutHidingFailure(
      'restore showing only online colleagues',
      () async =>
          robot.restoreShowOnlineColleaguesOnly(showedOnlineColleaguesOnly),
    );
  }
}

Future<void> _userCanSearchColleagues(
  ContactsRobot robot,
  Colleague colleague,
) async {
  final term = colleague.name.toLowerCase();
  final otherColleague = robot.colleagues.firstWhereOrNull(
    (other) =>
        other._hasName &&
        !other.name.toLowerCase().contains(term) &&
        !(other.number ?? '').contains(term),
  );

  TestLog.step('🔎', 'Searching for "${colleague.name}"');
  await robot.search(colleague.name);
  await robot.waitForListToShow(colleague.name);

  if (otherColleague != null) {
    TestLog.step('🙈', 'Expecting "${otherColleague.name}" to be hidden');
    await robot.waitForListToNotShow(otherColleague.name);
  }
}

Future<void> _userCanSeeAColleaguesDetails(
  ContactsRobot robot,
  Colleague colleague,
) async {
  TestLog.step('🪪', 'Opening the details of "${colleague.name}"');
  await robot.openDetails(colleague.name);

  robot.verifyDetailsShowName(colleague.name);
  if (colleague.number case final number?) {
    robot.verifyDetailsShowPhoneNumber(number);
  }
  robot.verifyDetailsShowAvailabilityOf(colleague.id);

  await robot.goBack();
}

Future<void> _userCanHideOfflineColleagues(ContactsRobot robot) async {
  final onlineColleagues = robot.colleagues.where((c) => c.isOnline).toList();

  // Searching narrows the list to this colleague, so whether they are shown
  // doesn't depend on where they are in a long list.
  final offlineColleague = robot.colleagues.firstWhereOrNull(
    (colleague) =>
        colleague._hasName &&
        !colleague.isOnline &&
        onlineColleagues.none(
          (online) => online.name.toLowerCase().contains(
            colleague.name.toLowerCase(),
          ),
        ),
  );

  if (offlineColleague == null) {
    throw TestFailure(
      'The test account should have an offline colleague, whose name is not '
      "part of an online colleague's name, to hide",
    );
  }

  TestLog.step(
    '💤',
    'Hiding and showing the offline colleague "${offlineColleague.name}"',
  );
  await robot.search(offlineColleague.name);
  await robot.waitForListToShow(offlineColleague.name);

  await robot.setShowOnlineColleaguesOnly(true);
  await robot.waitForListToNotShow(offlineColleague.name);

  await robot.setShowOnlineColleaguesOnly(false);
  await robot.waitForListToShow(offlineColleague.name);

  await robot.clearSearch();
}

Future<void> _userCanManageASharedContact(
  ContactsRobot robot,
  CallingRobot? callingRobot,
) async {
  final uniqueId = DateTime.now().millisecondsSinceEpoch.toString();
  final phoneNumber = TestEnv.integrationTestCallingPhoneNumber;

  final contact = SharedContact(
    id: null,
    givenName: _testContactGivenName,
    familyName: 'Contact $uniqueId',
  );
  final editedContact = contact.copyWith(familyName: 'Edited $uniqueId');

  TestLog.detail('Shared contact', contact.displayName);
  TestLog.detail('Renamed to', editedContact.displayName);
  TestLog.detail('Phone number', phoneNumber);

  await robot.openTab(ColltactTab.sharedContact);

  try {
    TestLog.step('➕', 'Adding the shared contact');
    await robot.tapAddSharedContactButton();
    await robot.fillInSharedContactForm(
      givenName: contact.givenName!,
      familyName: contact.familyName!,
      phoneNumber: phoneNumber,
    );
    await robot.saveSharedContactForm();
    await robot.waitForSharedContact(contact.displayName);

    await robot.search(uniqueId);
    await robot.waitForListToShow(contact.displayName);

    await robot.openDetails(contact.displayName);
    robot.verifyDetailsShowName(contact.displayName);
    robot.verifyDetailsShowPhoneNumber(phoneNumber);

    if (callingRobot != null) {
      await _userCanCallASharedContact(
        robot,
        callingRobot,
        contact.displayName,
        phoneNumber,
      );
    } else {
      TestLog.step(
        '⏭️',
        'Not calling the shared contact: this device cannot place a real call',
      );
    }

    TestLog.step('✏️', 'Renaming the shared contact');
    await robot.tapEditButton();
    await robot.changeSharedContactFamilyName(editedContact.familyName!);
    await robot.saveSharedContactForm();
    await robot.waitForDetailsToShowName(editedContact.displayName);

    await robot.goBack();
    await robot.waitForListToShow(editedContact.displayName);
    await robot.waitForListToNotShow(contact.displayName);

    TestLog.step('🗑️', 'Deleting the shared contact');
    await robot.openDetails(editedContact.displayName);
    await robot.tapEditButton();
    await robot.deleteSharedContact();
    await robot.waitForSharedContactToBeDeleted(editedContact.displayName);
    await robot.waitForListToNotShow(editedContact.displayName);

    await robot.clearSearch();
  } finally {
    await _withoutHidingFailure(
      'delete the shared contacts created by the tests',
      () => robot.deleteSharedContactsWithGivenName(_testContactGivenName),
    );
  }
}

Future<void> _userCanCallASharedContact(
  ContactsRobot robot,
  CallingRobot callingRobot,
  String name,
  String phoneNumber,
) async {
  TestLog.step('📞', 'Calling the shared contact on $phoneNumber');
  await robot.tapPhoneNumberInDetails(phoneNumber);
  await callingRobot.waitForCallToConnect();
  await callingRobot.verifyCallDuration();

  // The outgoing call tests check the recording of the latest call to this
  // number from the last minute, which could be this one, so it should last
  // long enough to pass that check.
  await callingRobot.waitFor(const Duration(seconds: 6));

  await callingRobot.tapHangUpButton();
  await callingRobot.verifyCallScreenIsDismissed();

  await robot.waitForDetailsToShowName(name);
}

Future<void> _userCanSeePhoneContacts(ContactsRobot robot) async {
  await robot.openTab(ColltactTab.contacts);
  robot.verifyPhoneContactsTabShowsContactsOrEmptyState();

  TestLog.detail('Phone contacts on the device', robot.phoneContacts.length);

  if (!Platform.isAndroid) {
    TestLog.step(
      '⏭️',
      'Not adding a phone contact: on iOS the contacts permission is only '
          'mocked, so writing to the address book would prompt for access',
    );
    return;
  }

  final uniqueId = DateTime.now().millisecondsSinceEpoch.toString();
  TestLog.detail('Phone contact', '$_testContactGivenName Device $uniqueId');
  TestLog.detail('Phone number', fakeMobileNumber);

  // The app keeps showing the last contact once the device has none left, so
  // removal can only be seen when there are other contacts.
  final hasOtherPhoneContacts = robot.phoneContacts.isNotEmpty;

  try {
    await robot.addDeviceContact(
      givenName: _testContactGivenName,
      familyName: 'Device $uniqueId',
      phoneNumber: fakeMobileNumber,
    );
    final name = await robot.waitForPhoneContactNamedWith(uniqueId);

    await robot.search(uniqueId);
    await robot.waitForListToShow(name);

    await robot.openDetails(name);
    robot.verifyDetailsShowName(name);
    robot.verifyDetailsShowPhoneNumber(fakeMobileNumber);
    await robot.goBack();

    await robot.clearSearch();
  } finally {
    await _withoutHidingFailure(
      'delete the device contacts created by the tests',
      () => robot.deleteDeviceContactsWithGivenName(_testContactGivenName),
    );
  }

  if (hasOtherPhoneContacts) {
    await robot.waitForPhoneContactToBeRemoved(uniqueId);
  }
}

/// Cleanup runs after a failure too, where throwing would replace the error
/// that explains the failure.
Future<void> _withoutHidingFailure(
  String description,
  Future<void> Function() cleanUp,
) async {
  try {
    await cleanUp();
  } catch (error) {
    TestLog.warning('Could not $description: $error');
  }
}

extension on Colleague {
  bool get _hasName => name.trim().isNotEmpty;
}
