import 'package:flutter_test/flutter_test.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vialer/data/models/user/user.dart';
import 'package:vialer/data/repositories/voipgrid/user_permissions.dart';
import 'package:vialer/domain/usecases/user/get_logged_in_user.dart';
import 'package:vialer/presentation/features/main_page.dart';
import 'package:vialer/presentation/features/onboarding/pages/login/login_page.dart';
import 'package:vialer/presentation/features/onboarding/pages/mobile_number/mobile_number_page.dart';
import 'package:vialer/presentation/features/onboarding/pages/password_forgotten/password_forgotten_page.dart';
import 'package:vialer/presentation/features/settings/widgets/tile/link/sub_page.dart';
import 'package:vialer/presentation/shared/widgets/error.dart';
import 'package:vialer/presentation/shared/widgets/notice/banner.dart';
import 'package:vialer/presentation/shared/widgets/stylized_button.dart';
import 'package:vialer/presentation/util/brand.dart';

import '../utils/test_extensions.dart';
import 'integration_test_robot.dart';

/// Covers logging in and the onboarding steps that follow it, so it starts on
/// the login page rather than the home screen.
class OnboardingRobot extends IntegrationTestRobot {
  OnboardingRobot(super.tester);

  @override
  bool get startsFromHome => false;

  /// Fills in and submits the login form without assuming the login succeeds,
  /// unlike [TestExtensions.loginWithCredentials].
  Future<void> submitLoginForm({
    required String email,
    required String password,
  }) async {
    await _waitForLoginPage();

    await tester.enterText(find.byKey(LoginPage.keys.emailField), email);
    await tester.enterText(find.byKey(LoginPage.keys.passwordField), password);

    await tester.tap(find.byKey(LoginPage.keys.loginButton));
    await tester.pumpAndSettle();
  }

  Future<void> verifyOnlyEmailFormatErrorIsShown() =>
      _verifyFormatErrors(email: true, password: false);

  Future<void> verifyOnlyPasswordFormatErrorIsShown() =>
      _verifyFormatErrors(email: false, password: true);

  Future<void> verifyBothFormatErrorsAreShown() =>
      _verifyFormatErrors(email: true, password: true);

  Future<void> _verifyFormatErrors({
    required bool email,
    required bool password,
  }) async {
    await tester.pumpUntil(
      () =>
          _isErrorVisible(LoginPage.keys.wrongEmailFormatError) == email &&
          _isErrorVisible(LoginPage.keys.wrongPasswordFormatError) == password,
      reason:
          'The email format error should be ${_shownOrHidden(email)} and the '
          'password format error ${_shownOrHidden(password)}',
    );
  }

  String _shownOrHidden(bool shown) => shown ? 'shown' : 'hidden';

  /// The format errors stay in the tree when hidden, so their visibility is
  /// read from the widget instead.
  bool _isErrorVisible(Key key) =>
      tester.widget<ErrorAlert>(find.byKey(key)).visible;

  String get enteredLoginEmail =>
      _editableTextIn(find.byKey(LoginPage.keys.emailField)).controller.text;

  Future<void> openForgottenPasswordPage() async {
    final label = tester.msg.onboarding.login.button.forgotPassword
        .toLowerCase();
    // The label is upper cased on Android.
    final button = find.descendant(
      of: find.byType(LoginPage),
      matching: find.byWidgetPredicate(
        (widget) => widget is Text && widget.data?.toLowerCase() == label,
      ),
    );

    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);

    await tester.pumpUntilFound(
      find.byType(PasswordForgottenPage),
      reason: 'The forgotten password page should open from the login page',
    );
  }

  void verifyForgottenPasswordPageIsPrefilledWith(String email) {
    final page = find.byType(PasswordForgottenPage);

    expect(
      find.descendant(
        of: page,
        matching: find.text(tester.msg.onboarding.passwordForgotten.title),
      ),
      findsOneWidget,
      reason: 'The forgotten password page should show its title',
    );

    expect(
      _editableTextIn(page).controller.text,
      email,
      reason: 'The email entered on the login page should be carried over',
    );
  }

  /// Closes the page without requesting a reset, which would send a real
  /// email.
  Future<void> closeForgottenPasswordPage() async {
    await tester.tap(
      find.descendant(
        of: find.byType(PasswordForgottenPage),
        matching: find.byIcon(Icons.close),
      ),
    );

    await tester.pumpUntilGone(
      find.byType(PasswordForgottenPage),
      reason: 'The forgotten password page should close',
    );
  }

  Future<void> verifyLoginPageIsShownAgain() async {
    await _waitForLoginPage();

    expect(
      find.byType(SnackBar),
      findsNothing,
      reason: 'No reset confirmation should be shown when nothing was sent',
    );
  }

  Future<void> _waitForLoginPage() => tester.pumpUntilHittable(
    find.byKey(LoginPage.keys.emailField),
    reason: 'The login page should be shown',
  );

  Future<void> waitForMobileNumberStep() => tester.pumpUntilHittable(
    find.byKey(MobileNumberPage.keys.field),
    timeout: const Duration(seconds: 60),
    reason: 'Logging in should move onboarding on to the mobile number step',
  );

  /// The field is filled with the number already on the account.
  String get enteredMobileNumber =>
      _editableTextIn(find.byKey(MobileNumberPage.keys.field)).controller.text;

  Future<void> enterMobileNumber(String number) async {
    await tester.enterText(find.byKey(MobileNumberPage.keys.field), number);
    await tester.pumpAndSettle();
  }

  /// Numbers are validated remotely as they are typed. Only continuing saves
  /// the number, and continuing is blocked while it is rejected.
  Future<void> verifyMobileNumberIsRejected() => tester.pumpUntil(
    () => _isMobileNumberErrorVisible && !_canContinueFromMobileNumber,
    reason:
        'An invalid mobile number should show an error and block continuing',
  );

  Future<void> verifyMobileNumberIsAccepted() => tester.pumpUntil(
    () => !_isMobileNumberErrorVisible && _canContinueFromMobileNumber,
    reason: 'The mobile number should be accepted again',
  );

  bool get _isMobileNumberErrorVisible => tester
      .widget<ErrorAlert>(
        find.descendant(
          of: find.byType(MobileNumberPage),
          matching: find.byType(ErrorAlert),
        ),
      )
      .visible;

  bool get _canContinueFromMobileNumber =>
      tester
          .widget<StylizedButton>(
            find.byKey(MobileNumberPage.keys.continueButton),
          )
          .onPressed !=
      null;

  User get _user => GetLoggedInUserUseCase()();

  void verifyUserCannotUseVoip() {
    expect(
      _user.isAllowedVoipCalling,
      isFalse,
      reason: 'This user should have no app account, so no VoIP calling',
    );
  }

  /// The wording depends on whether the user may pick an app account
  /// themselves, which is read from the user rather than assumed.
  Future<void> verifyNoAppAccountNoticeIsShown() async {
    final strings = tester.msg.main.notice.noAppAccount;

    String expectedContent() {
      final appName = tester.element(find.byType(MainPage)).brand.appName;
      return _user.hasPermission(Permission.canChangeAppAccount)
          ? strings.content(appName)
          : strings.noPermission.content;
    }

    await tester.pumpUntil(
      () =>
          tester.any(_inNoticeBanner(find.text(strings.title))) &&
          tester.any(_inNoticeBanner(find.text(expectedContent()))),
      reason:
          'A user without an app account should be told they cannot receive '
          'calls in the app',
    );
  }

  Finder _inNoticeBanner(Finder finder) =>
      find.descendant(of: find.byType(NoticeBanner), matching: finder);

  /// Logging out lives on the user's own settings page.
  Future<void> logout() async {
    await tester.navigateToSettingsTab();

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

  EditableText _editableTextIn(Finder finder) => tester.widget<EditableText>(
    find.descendant(of: finder, matching: find.byType(EditableText)),
  );
}
