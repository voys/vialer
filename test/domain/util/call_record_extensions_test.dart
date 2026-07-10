import 'package:test/test.dart';
import 'package:vialer/data/models/call_records/call_record.dart';
import 'package:vialer/data/models/call_records/item.dart';
import 'package:vialer/data/models/colltacts/contact.dart';
import 'package:vialer/domain/util/call_record_extensions.dart';

void main() {
  group('hasThirdPartyNumber', () {
    test('is true for a call with an outside number', () {
      expect(_callRecord().hasThirdPartyNumber, isTrue);
    });

    test('is true for a call with a colleague', () {
      expect(
        _callRecord(callType: CallType.colleague).hasThirdPartyNumber,
        isTrue,
      );
    });

    test('is false when the number is blank', () {
      expect(_callRecord(callerNumber: '').hasThirdPartyNumber, isFalse);
    });
  });

  group('thirdPartyContact', () {
    test('is null for a call record without a contact', () {
      expect(_callRecord().thirdPartyContact, isNull);
    });

    test('is the matched contact for a personal call record', () {
      final contact = _contact();

      expect(_callRecord().withContact(contact).thirdPartyContact, contact);
    });

    test('is the caller contact for an inbound client call', () {
      final contact = _contact();
      final callRecord = _clientCallRecord().withContact(
        callerContact: contact,
        destinationContact: null,
      );

      expect(callRecord.thirdPartyContact, contact);
    });

    test('is the destination contact for an outbound client call', () {
      final contact = _contact();
      final callRecord = _clientCallRecord(
        callDirection: Direction.outbound,
      ).withContact(callerContact: null, destinationContact: contact);

      expect(callRecord.thirdPartyContact, contact);
    });
  });
}

CallRecord _callRecord({
  CallType callType = CallType.outside,
  String callerNumber = '+31640366644',
}) => CallRecordWithoutContact(
  id: 'dummyId',
  callType: callType,
  callDirection: Direction.inbound,
  answered: true,
  answeredElsewhere: false,
  duration: const Duration(seconds: 5),
  date: DateTime.now(),
  caller: CallParty(
    name: 'CallerName',
    number: callerNumber,
    type: CallerType.other,
  ),
  destination: const CallParty(
    name: 'DestinationName',
    number: '241',
    type: CallerType.account,
  ),
);

ClientCallRecord _clientCallRecord({
  CallType callType = CallType.outside,
  Direction callDirection = Direction.inbound,
}) => ClientCallRecord(
  id: 'dummyId',
  callType: callType,
  callDirection: callDirection,
  answered: true,
  answeredElsewhere: false,
  duration: const Duration(seconds: 5),
  date: DateTime.now(),
  caller: const CallParty(
    name: 'CallerName',
    number: '+31640366644',
    type: CallerType.other,
  ),
  destination: const CallParty(
    name: 'DestinationName',
    number: '241',
    type: CallerType.account,
  ),
  didTargetColleague: false,
  didTargetLoggedInUser: true,
  wasInitiatedByColleague: false,
  wasInitiatedByLoggedInUser: false,
);

Contact _contact() => const Contact(
  givenName: 'Foo',
  middleName: 'Bar',
  familyName: 'Baz',
  chosenName: 'Fred',
  phoneNumbers: [Item(label: 'Mobile', value: '+31640366644')],
  emails: [],
  identifier: '123',
  company: 'acme',
  avatarPath: null,
);
