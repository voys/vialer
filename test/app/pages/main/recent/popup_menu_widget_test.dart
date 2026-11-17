import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vialer/data/models/call_records/call_record.dart';
import 'package:vialer/data/models/call_records/item.dart';
import 'package:vialer/data/models/colltacts/contact.dart';
import 'package:vialer/data/models/user/brand.dart';
import 'package:vialer/presentation/features/recent/widgets/popup_menu.dart';
import 'package:vialer/presentation/resources/localizations.dart';
import 'package:vialer/presentation/resources/theme.dart';
import 'package:vialer/presentation/shared/widgets/brand_provider/widget.dart';

void main() {
  Future<void> pumpPopupMenu(WidgetTester tester, CallRecord callRecord) async {
    await tester.pumpWidget(
      TestApp(
        child: Localizations(
          locale: const Locale('en'),
          delegates: const [
            VialerLocalizations.delegate,
            ...GlobalMaterialLocalizations.delegates,
          ],
          child: RecentItemPopupMenu(
            callRecord: callRecord,
            onPopupMenuItemPress: (_) {},
          ),
        ),
      ),
    );

    await tester.tap(find.byType(PopupMenuButton<RecentCallMenuAction>));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'The menu shows the add contact option when there is no matching contact',
    (tester) async {
      await pumpPopupMenu(tester, _callRecord());

      expect(find.text('Add as shared contact'), findsOneWidget);
      expect(find.text('View contact'), findsNothing);
    },
  );

  testWidgets(
    'The menu shows "View contact" when the call has a matching contact',
    (tester) async {
      await pumpPopupMenu(tester, _callRecord().withContact(_contact()));

      expect(find.text('View contact'), findsOneWidget);
      expect(find.text('Add as shared contact'), findsNothing);
    },
  );

  testWidgets(
    'The menu shows the add contact option for a call with a colleague',
    (tester) async {
      await pumpPopupMenu(tester, _callRecord(callType: CallType.colleague));

      expect(find.text('Add as shared contact'), findsOneWidget);
      expect(find.text('View contact'), findsNothing);
    },
  );
}

CallRecord _callRecord({CallType callType = CallType.outside}) =>
    CallRecordWithoutContact(
      id: 'dummyId',
      callType: callType,
      callDirection: Direction.inbound,
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

class TestApp extends StatelessWidget {
  TestApp({required this.child, super.key});

  final Widget child;
  final _fakeUrl = Uri.parse('https://fake.url');

  @override
  Widget build(BuildContext context) {
    return BrandProvider(
      brand: Brand(
        identifier: 'vialer',
        appId: 'com.voipgrid.vialer',
        appName: 'Vialer',
        url: _fakeUrl,
        middlewareUrl: _fakeUrl,
        voipgridUrl: _fakeUrl,
        sipUrl: _fakeUrl,
        businessAvailabilityUrl: _fakeUrl,
        openingHoursBasicUrl: _fakeUrl,
        resgateUrl: _fakeUrl,
        privacyPolicyUrl: _fakeUrl,
        signUpUrl: null,
        availabilityServiceUrl: _fakeUrl,
        sharedContactsUrl: _fakeUrl,
        phoneNumberValidationUrl: _fakeUrl,
        featureAnnouncementsUrl: _fakeUrl,
        supportUrl: _fakeUrl,
        supportUrlNL: _fakeUrl,
      ),
      child: Builder(
        builder: (context) {
          return MaterialApp(
            title: context.brand.appName,
            theme: context.brand.theme.themeData,
            home: Scaffold(body: child),
          );
        },
      ),
    );
  }
}
