import 'package:flutter_test/flutter_test.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:vialer/presentation/features/onboarding/pages/login/login_page.dart';
import 'package:vialer/presentation/features/settings/widgets/tile/link/sub_page.dart';

import '../utils/test_extensions.dart';

Future<void> runCleanupTests(IntegrationTestContext context) async {
  await _userCanLogoutOfTheApp(context.tester);
}

Future<void> _userCanLogoutOfTheApp(
  WidgetTester tester,
) async {
  await tester.navigateToContactsTab();
  await tester.navigateToSettingsTab();

  // The logout button lives on the user's own settings page.
  await tester.tap(
    find.byWidgetPredicate(
      (widget) =>
          widget is SubPageLinkTile &&
          widget.icon == FontAwesomeIcons.circleUser,
    ),
  );
  await tester.pumpAndSettle();

  final logoutButton = find.text(tester.msg.main.settings.buttons.logout);
  await tester.ensureVisible(logoutButton);
  await tester.pumpAndSettle();
  await tester.tap(logoutButton);

  await tester.pumpUntilFound(
    find.byType(LoginPage),
    reason: 'The login page should be shown after logging out',
  );
}
