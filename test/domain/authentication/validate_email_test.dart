import 'package:flutter_test/flutter_test.dart';
import 'package:vialer/domain/usecases/authentication/validate_email.dart';

void main() {
  final validateEmail = ValidateEmail();

  group('hasValidEmailFormat', () {
    test('returns true for valid email format', () async {
      const email = 'test@example.com';
      final result = await validateEmail(email);
      expect(result, true);
    });

    test('returns false for email without local part', () async {
      const email = '@example.com';
      final result = await validateEmail(email);
      expect(result, false);
    });

    test('returns false for email without domain part', () async {
      const email = 'test@';
      final result = await validateEmail(email);
      expect(result, false);
    });

    test('returns false for email without top-level domain part', () async {
      const email = 'test@example';
      final result = await validateEmail(email);
      expect(result, false);
    });

    test('returns false for email with invalid characters', () async {
      const email = 'test@example!com';
      final result = await validateEmail(email);
      expect(result, false);
    });
  });
}
