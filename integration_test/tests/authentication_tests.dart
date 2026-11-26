import 'dart:io' show Platform;

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vialer/presentation/features/main_page.dart';
import 'package:vialer/presentation/shared/widgets/notice/banner.dart';

import '../robots/onboarding_robot.dart';
import '../utils/test_env.dart';
import '../utils/test_extensions.dart';

Future<void> runAuthenticationTests(IntegrationTestContext context) async {
  final tester = context.tester;
  final robot = OnboardingRobot(tester);
  await _userIsToldWhenCredentialsAreBadlyFormatted(robot);
  await _userCannotLoginWithInvalidCredentials(tester);
  await _userCanOpenAndCloseTheForgottenPasswordPage(robot);
  await _userWithoutAnAppAccountIsToldTheyCannotReceiveCalls(robot);
  await _userCanLoginWithValidCredentials(tester);
  await _userCanCloseTheBatteryOptimizationWarning(tester);
}

/// These are caught by the form itself, so no login is attempted.
Future<void> _userIsToldWhenCredentialsAreBadlyFormatted(
  OnboardingRobot robot,
) async {
  await robot.submitLoginForm(email: 'not-an-email', password: 'abc123!');
  await robot.verifyOnlyEmailFormatErrorIsShown();

  // A password needs at least 6 characters, one of which is not a letter.
  await robot.submitLoginForm(
    email: 'someone@integration-test.invalid',
    password: 'onlyletters',
  );
  await robot.verifyOnlyPasswordFormatErrorIsShown();

  await robot.submitLoginForm(email: '', password: '');
  await robot.verifyBothFormatErrorsAreShown();
}

Future<void> _userCannotLoginWithInvalidCredentials(
  WidgetTester tester,
) async {
  // Correctly formatted, so the login is attempted rather than rejected by
  // the form validation.
  await tester.loginWithCredentials(
    'invalid@integration-test.invalid',
    'invalid-password',
  );

  await tester.pumpUntilFound(
    find.text(tester.msg.onboarding.login.error.wrongCombination.title),
    reason: 'Logging in with invalid credentials should fail',
  );
}

Future<void> _userCanOpenAndCloseTheForgottenPasswordPage(
  OnboardingRobot robot,
) async {
  final email = robot.enteredLoginEmail;

  await robot.openForgottenPasswordPage();
  robot.verifyForgottenPasswordPageIsPrefilledWith(email);
  await robot.closeForgottenPasswordPage();
  await robot.verifyLoginPageIsShownAgain();
}

/// Such a user can still use the app, but cannot receive calls in it. They are
/// logged out again so the main user can log in after.
///
/// The mobile number step is checked here as well. Nothing entered is saved
/// until continuing, and the original number is put back before that, which
/// leaves the account untouched.
Future<void> _userWithoutAnAppAccountIsToldTheyCannotReceiveCalls(
  OnboardingRobot robot,
) async {
  final tester = robot.tester;
  final username = TestEnv.integrationTestUserWithoutAppAccountUsername;
  final password = TestEnv.integrationTestUserWithoutAppAccountPassword;

  if (username.isEmpty || password.isEmpty) {
    throw TestFailure(
      'Update .env with INTEGRATION_TEST_USER_WITHOUT_APP_ACCOUNT_USERNAME and '
      'INTEGRATION_TEST_USER_WITHOUT_APP_ACCOUNT_PASSWORD before running '
      'integration tests.',
    );
  }

  await tester.loginWithCredentials(username, password);

  await robot.waitForMobileNumberStep();
  final originalMobileNumber = robot.enteredMobileNumber;
  await robot.enterMobileNumber('12345');
  await robot.verifyMobileNumberIsRejected();
  await robot.enterMobileNumber(fakeMobileNumber);
  await robot.verifyMobileNumberIsAccepted();
  await robot.enterMobileNumber(originalMobileNumber);
  await robot.verifyMobileNumberIsAccepted();

  await tester.completeOnboarding();

  robot.verifyUserCannotUseVoip();
  await robot.verifyNoAppAccountNoticeIsShown();

  await robot.logout();
}

Future<void> _userCanLoginWithValidCredentials(
  WidgetTester tester,
) async {
  await tester.loginWithCredentials();
  await tester.completeOnboarding();

  expect(find.byType(MainPage), findsOneWidget);
}

/// Ignoring battery optimizations can't be granted up front like the other
/// permissions, so on Android the app always warns about it after logging in.
Future<void> _userCanCloseTheBatteryOptimizationWarning(
  WidgetTester tester,
) async {
  if (!Platform.isAndroid) return;

  final banner = find.byType(NoticeBanner);

  await tester.pumpUntilFound(
    find.descendant(
      of: banner,
      matching: find.text(
        tester.msg.onboarding.permission.ignoreBatteryOptimizations.title,
      ),
    ),
    reason: 'The battery optimization warning should be shown after login',
  );

  final closeLabel = tester.msg.generic.button.close.toLowerCase();
  await tester.tap(
    find.descendant(
      of: banner,
      matching: find.byWidgetPredicate(
        (widget) => widget is Text && widget.data?.toLowerCase() == closeLabel,
      ),
    ),
  );
  await tester.pumpAndSettle();

  expect(
    banner,
    findsNothing,
    reason: 'The warning should be gone once it is closed',
  );
}
