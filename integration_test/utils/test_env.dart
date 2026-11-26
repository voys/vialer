import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Environment variables only used by the integration tests. They live in the
/// same `.env` file as the app's own, which the app loads while bootstrapping,
/// so these can only be read once the app has been bootstrapped.
abstract class TestEnv {
  static String get integrationTestUser1Username =>
      _get('INTEGRATION_TEST_USER_1_USERNAME');

  static String get integrationTestUser1Password =>
      _get('INTEGRATION_TEST_USER_1_PASSWORD');

  /// A user whose VoIPGRID account has no app account, so they cannot call
  /// through the app.
  static String get integrationTestUserWithoutAppAccountUsername =>
      _get('INTEGRATION_TEST_USER_WITHOUT_APP_ACCOUNT_USERNAME');

  static String get integrationTestUserWithoutAppAccountPassword =>
      _get('INTEGRATION_TEST_USER_WITHOUT_APP_ACCOUNT_PASSWORD');

  static String get integrationTestCallingPhoneNumber =>
      _get('INTEGRATION_TEST_CALLING_PHONE_NUMBER');

  static String get integrationTestIncomingCallNumber =>
      _get('INTEGRATION_TEST_INCOMING_CALL_NUMBER');

  static String _get(String key) => dotenv.env[key] ?? '';
}
