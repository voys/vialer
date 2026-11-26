import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vialer/data/models/onboarding/step.dart';
import 'package:vialer/presentation/features/colltacts/pages/colltacts_page.dart';
import 'package:vialer/presentation/features/main_page.dart';
import 'package:vialer/presentation/features/onboarding/pages/info/info_page.dart';
import 'package:vialer/presentation/features/onboarding/pages/login/login_page.dart';
import 'package:vialer/presentation/features/onboarding/pages/mobile_number/mobile_number_page.dart';
import 'package:vialer/presentation/features/onboarding/widgets/page.dart';
import 'package:vialer/presentation/features/recent/recent_calls_page.dart';
import 'package:vialer/presentation/features/settings/pages/settings.dart';
import 'package:vialer/presentation/resources/localizations.dart';
import 'package:vialer/presentation/resources/messages.i18n.dart';

import 'test_env.dart';

extension TestExtensions on WidgetTester {
  /// The strings in the language the app is running in, so tests can find
  /// widgets by their text on a device in any locale.
  Messages get msg => element(find.byType(Navigator).first).msg;

  Future<void> loginWithCredentials([
    String? username,
    String? password,
  ]) async {
    username ??= TestEnv.integrationTestUser1Username;
    password ??= TestEnv.integrationTestUser1Password;

    if (username.isEmpty || password.isEmpty) {
      throw TestFailure(
        'Integration test credentials are empty. '
        'Update .env with INTEGRATION_TEST_USER_1_USERNAME and '
        'INTEGRATION_TEST_USER_1_PASSWORD before running integration tests.',
      );
    }

    // The login page fades in after an intro animation.
    await pumpUntilHittable(
      find.byKey(LoginPage.keys.emailField),
      reason: 'The login page should be shown',
    );

    await enterText(find.byKey(LoginPage.keys.emailField), username);
    await enterText(find.byKey(LoginPage.keys.passwordField), password);

    await tap(find.byKey(LoginPage.keys.loginButton));
    await pumpAndSettle();
  }

  /// Goes through the onboarding steps that follow a successful login, until
  /// the main page is shown.
  Future<void> completeOnboarding() async {
    await pumpUntil(
      () => _currentOnboardingStep == OnboardingStep.mobileNumber,
      timeout: const Duration(seconds: 60),
      reason: 'Logging in should move onboarding on to the mobile number step',
    );

    await tap(find.byKey(MobileNumberPage.keys.continueButton).hitTestable());
    await pumpAndSettle();

    // Runtime permissions are granted up front (or mocked on iOS), and
    // requesting them is skipped during integration tests, so these pages
    // only need to be continued through.
    for (var i = 0; i < OnboardingStep.values.length; i++) {
      final step = _currentOnboardingStep;
      if (step == null || step == OnboardingStep.welcome) break;

      await tap(find.byKey(InfoPage.keys.continueButton).hitTestable().first);
      await pumpAndSettle();
    }

    await pumpUntilFound(
      find.byType(MainPage),
      reason: 'The main page should be shown once onboarding completes',
    );
  }

  OnboardingStep? get _currentOnboardingStep {
    final state = OnboardingPage.keys.page.currentState;
    if (state == null || !state.pageController.hasClients) return null;

    return state.currentPages.keys.elementAt(
      state.pageController.page!.round(),
    );
  }

  Future<void> navigateToContactsTab() async {
    await _tapTab(msg.main.contacts.menu.title);
    _verifyPageIsVisible<ColltactsPage>();
  }

  Future<void> navigateToRecentsTab() async {
    await _tapTab(msg.main.recent.menu.title);
    _verifyPageIsVisible<RecentCallsPage>();
  }

  Future<void> navigateToSettingsTab() async {
    await _tapTab(msg.main.settings.menu.title);
    _verifyPageIsVisible<SettingsPage>();
  }

  Future<void> _tapTab(String label) async {
    await tap(
      find.descendant(
        of: find.byKey(MainPage.keys.navigationBar),
        matching: find.text(label),
      ),
    );
    await pumpAndSettle();
  }

  void _verifyPageIsVisible<T extends Widget>() {
    expect(
      find.byType(T),
      findsOneWidget,
      reason: '$T should be visible after navigation',
    );
  }

  /// Taps the page's back button. [pageBack] finds it by its English tooltip,
  /// which fails on a device in another language, so it is only the fallback
  /// for pages without a Material back button.
  Future<void> goBack({int times = 1}) async {
    for (var i = 0; i < times; i++) {
      await pumpAndSettle();
      final backButton = find.byType(BackButton).hitTestable();
      if (any(backButton)) {
        await tap(backButton.last);
      } else {
        await pageBack();
      }
      await pumpAndSettle();
    }
  }

  Future<void> pumpUntil(
    bool Function() condition, {
    Duration timeout = _defaultPumpUntilTimeout,
    String? reason,
    bool settle = true,
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
    if (settle) await pumpAndSettle();
  }

  Future<void> pumpUntilFound(
    Finder finder, {
    Duration timeout = _defaultPumpUntilTimeout,
    String? reason,
    bool settle = true,
  }) => pumpUntil(
    () => any(finder),
    timeout: timeout,
    reason: reason ?? 'Expected to find $finder within $timeout',
    settle: settle,
  );

  Future<void> pumpUntilGone(
    Finder finder, {
    Duration timeout = _defaultPumpUntilTimeout,
    String? reason,
    bool settle = true,
  }) => pumpUntil(
    () => !any(finder),
    timeout: timeout,
    reason: reason ?? 'Expected $finder to disappear within $timeout',
    settle: settle,
  );

  Future<void> pumpUntilHittable(
    Finder finder, {
    Duration timeout = _defaultPumpUntilTimeout,
    String? reason,
    bool settle = true,
  }) => pumpUntil(
    () => any(finder.hitTestable()),
    timeout: timeout,
    reason: reason ?? 'Expected $finder to be hittable within $timeout',
    settle: settle,
  );

  /// Waits without pumping, for while a native screen covers the app: Flutter
  /// draws no frames then, so [pump] would block until the app is back in
  /// front.
  Future<void> waitUntilWithoutPumping(
    bool Function() condition, {
    required String reason,
    Duration timeout = _defaultPumpUntilTimeout,
  }) async {
    const interval = Duration(milliseconds: 100);
    var elapsed = Duration.zero;
    while (!condition()) {
      if (elapsed >= timeout) throw TestFailure(reason);
      await Future<void>.delayed(interval);
      elapsed += interval;
    }
  }

  /// Waits for a native screen that covered the app to go away again, after
  /// which pumping works as usual.
  ///
  /// A pump only completes once the app draws frames again, which is a more
  /// reliable signal than the lifecycle state, which didn't always report the
  /// app as resumed after the native incoming call screen closed.
  Future<void> waitUntilAppIsInFront() => pump().timeout(
    _defaultPumpUntilTimeout,
    onTimeout: () => throw TestFailure(
      'The app should come back to the front within $_defaultPumpUntilTimeout',
    ),
  );

  /// Pumps one frame a second, rather than a single long pump, so the app
  /// keeps rendering while time passes.
  Future<void> pumpFor(Duration duration) async {
    const interval = Duration(seconds: 1);
    for (var elapsed = Duration.zero; elapsed < duration; elapsed += interval) {
      await pump(interval);
    }
  }
}

const _defaultPumpUntilTimeout = Duration(seconds: 30);

typedef IntegrationTestContext = ({
  WidgetTester tester,
  TestConfiguration config,
});

/// Which part of the integration test suite a run covers. Picked by
/// `./utils/bin/run-integration-tests` through `--suite=`, never inferred from
/// the environment.
enum IntegrationTestSuite {
  /// Everything, incoming calls included. The default for a local Android run,
  /// and what Codemagic runs on emulator.wtf, with baresip on the build machine
  /// reached through the egress tunnel.
  all,

  /// Only the incoming call tests. Authentication and cleanup always run.
  incomingCalls,

  /// Everything except the incoming call tests — outgoing calls included, since
  /// those only need the app itself. The default on emulator.wtf and iOS:
  /// receiving a call needs the device to reach baresip on this machine.
  ///
  /// The outgoing call tests drop out on a runner that cannot place a real
  /// call — the iOS simulator on CI — through [TestConfiguration.canPlaceRealCalls].
  withoutIncomingCalls;

  bool get includesIncomingCalls =>
      this != IntegrationTestSuite.withoutIncomingCalls;

  bool get everythingExceptIncomingCalls =>
      this != IntegrationTestSuite.incomingCalls;
}

typedef TestConfiguration = ({
  IntegrationTestSuite suite,
  bool canPlaceRealCalls,
  bool skipTestingCallMediaEstablished,
});

extension IntegrationTestEnvironment on WidgetTester {
  void ensureRunViaScript() {
    const runViaScript = bool.hasEnvironment('INTEGRATION_TEST_RUNNER');
    if (!runViaScript) {
      throw StateError(
        'Integration tests must be run via ./utils/bin/run-integration-tests, '
        'not directly with `flutter test` or `flutter drive`.',
      );
    }
  }
}
