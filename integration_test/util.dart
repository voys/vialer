import 'dart:async';

import 'package:dartx/dartx.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:vialer/data/models/onboarding/step.dart';
import 'package:vialer/presentation/features/main_page.dart';
import 'package:vialer/presentation/features/onboarding/pages/info/info_page.dart';
import 'package:vialer/presentation/features/onboarding/pages/login/login_page.dart';
import 'package:vialer/presentation/features/onboarding/pages/mobile_number/mobile_number_page.dart';
import 'package:vialer/presentation/features/onboarding/widgets/page.dart';
import 'package:vialer/presentation/main.dart' as app;
import 'package:vialer/presentation/main.dart';

import 'permission_mock.dart';

Future<void> runTest(
  List<String> name,
  WidgetTesterCallback test,
) async {
  assert(name.isNotEmpty, 'name must not be empty');

  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  mockPermissionsForIOS();

  unawaited(app.main());

  final fullName = name
      .mapIndexed((index, part) => index != name.lastIndex ? '$part: ' : part)
      .joinToString(separator: ' ');

  testWidgets(fullName, test);
}

class _IsInflatedMatcher extends Matcher {
  const _IsInflatedMatcher();

  @override
  Description describe(Description description) =>
      description.add('the widget(s) found are inflated');

  @override
  Description describeMismatch(
    covariant Finder item,
    Description mismatchDescription,
    Map<dynamic, dynamic> matchState,
    bool verbose,
  ) {
    var newDescription = mismatchDescription;
    for (final e in item.evaluate()) {
      if (e.size == Size.zero) {
        newDescription = newDescription.add('$e is not inflated');
      }
    }

    return newDescription;
  }

  @override
  bool matches(covariant Finder item, Map<dynamic, dynamic> matchState) =>
      item.evaluate().every((e) => e.size != Size.zero);
}

/// Asserts that the widget(s) found are inflated.
///
/// By "inflated", it's meant that the widget has a size. It does not check
/// whether the widget(s) are actually visible on screen.
const Matcher isInflated = _IsInflatedMatcher();

@immutable
class TestUser {
  const TestUser(this.email, this.password);

  final String email;
  final String password;
}

TestUser? _tester1;
TestUser? _tester2;
TestUser? _testUserWithoutAppAccount;
TestUser? _testUserWithEndUserPermissions;

TestUser get testUser1 => _tester1 ??= TestUser(
  dotenv.env['TEST_USER_1_EMAIL']!,
  dotenv.env['TEST_USER_1_PASSWORD']!,
);

TestUser get testUser2 => _tester2 ??= TestUser(
  dotenv.env['TEST_USER_2_EMAIL']!,
  dotenv.env['TEST_USER_2_PASSWORD']!,
);

TestUser get testUserWithoutAppAccount =>
    _testUserWithoutAppAccount ??= TestUser(
      dotenv.env['TEST_USER_WITHOUT_APP_ACCOUNT_EMAIL']!,
      dotenv.env['TEST_USER_WITHOUT_APP_ACCOUNT_PASSWORD']!,
    );

TestUser get testUserWithEndUserPermissions =>
    _testUserWithEndUserPermissions ??= TestUser(
      dotenv.env['TEST_USER_WITH_END_USER_PERMISSIONS_EMAIL']!,
      dotenv.env['TEST_USER_WITH_END_USER_PERMISSIONS_PASSWORD']!,
    );

extension OnboardingPageTesting on GlobalKey<OnboardingPageState> {
  /// Returns `null` if the onboarding is finished (and the OnboardingPage
  /// is not in the widget tree anymore).
  OnboardingStep? get currentStep => currentState?.currentPages.keys.elementAt(
    currentState!.pageController.page!.round(),
  );
}

const _pumpUntilTimeout = Duration(seconds: 30);

extension Util on WidgetTester {
  /// Pump until [condition] holds.
  ///
  /// [pumpAndSettle] cannot be used to wait for this app: it only returns once
  /// no frames are scheduled, and the websocket pushing availability updates
  /// keeps scheduling them, so it blocks until its own 10 minute timeout.
  Future<void> pumpUntil(
    bool Function() condition, {
    Duration timeout = _pumpUntilTimeout,
    String? reason,
  }) async {
    const interval = Duration(milliseconds: 100);
    var elapsed = Duration.zero;

    while (!condition()) {
      if (elapsed >= timeout) {
        throw TestFailure(reason ?? 'Condition not met within $timeout');
      }
      await pump(interval);
      elapsed += interval;
    }
  }

  Future<void> pumpUntilFound(
    Finder finder, {
    Duration timeout = _pumpUntilTimeout,
    String? reason,
  }) => pumpUntil(
    () => any(finder),
    timeout: timeout,
    reason: reason ?? 'Expected to find $finder within $timeout',
  );

  Future<void> waitForOnboardingIntroAnimation() => pumpUntilFound(
    find.byKey(LoginPage.keys.emailField).hitTestable(),
    reason: 'Expected the login page to become interactive',
  );

  /// Go through the onboarding process, by default as [testUser1].
  ///
  /// This method will return once the main page is shown.
  Future<void> completeOnboarding({TestUser? as}) async {
    await waitForOnboardingIntroAnimation();

    final user = as ?? testUser1;

    await enterText(
      find.byKey(LoginPage.keys.emailField),
      user.email,
    );

    await enterText(
      find.byKey(LoginPage.keys.passwordField),
      user.password,
    );

    OnboardingStep? onboardingStep() => OnboardingPage.keys.page.currentStep;

    await tap(find.byKey(LoginPage.keys.loginButton));
    await pumpUntil(
      () => onboardingStep() == OnboardingStep.mobileNumber,
      timeout: const Duration(seconds: 60),
      reason: 'Expected to reach the mobile number step after logging in',
    );

    await tap(find.byKey(MobileNumberPage.keys.continueButton));
    await pumpUntil(
      () => onboardingStep() != OnboardingStep.mobileNumber,
      reason: 'Expected to advance past the mobile number step',
    );

    // Go through call, contacts and microphone permission pages. Each tap must
    // land on a different page, otherwise permission_handler rejects the second
    // request as one already being in progress.
    var step = onboardingStep();
    while (step != null && step != OnboardingStep.welcome) {
      await tap(find.byKey(InfoPage.keys.continueButton));
      await pumpUntil(
        () => onboardingStep() != step,
        reason: 'Expected to advance past $step',
      );
      step = onboardingStep();
    }

    await pump(const Duration(seconds: 2));
  }

  Future<void> navigateTo(MainPageTab tab) async {
    App.navigateTo(tab);
    await pumpAndSettle(const Duration(seconds: 1));
  }
}
