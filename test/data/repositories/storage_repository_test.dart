import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vialer/data/models/user/user.dart';
import 'package:vialer/data/repositories/legacy/storage.dart';
import 'package:vialer/data/repositories/secure_storage/secure_storage_repository.dart';
import 'package:vialer/presentation/util/pigeon.dart';

@GenerateNiceMocks([MockSpec<NativeSecureStorage>()])
import 'storage_repository_test.mocks.dart';
import 'test_user.dart';

void main() {
  late SharedPreferences preferences;
  late MockNativeSecureStorage api;

  Future<StorageRepository> createStorage({
    Map<String, Object> preferenceValues = const {},
    Credentials? credentials,
  }) async {
    SharedPreferences.setMockInitialValues(preferenceValues);
    preferences = await SharedPreferences.getInstance();

    return StorageRepository.create(
      preferences,
      SecureStorageRepository(api, credentials ?? Credentials()),
    );
  }

  Map<String, dynamic> storedUserJson() =>
      jsonDecode(preferences.getString('system_user')!) as Map<String, dynamic>;

  Map<String, dynamic> userJsonWithoutCredentials() {
    final json = jsonDecode(jsonEncode(testUser)) as Map<String, dynamic>;
    json.remove('token');
    (json['voip'] as Map<String, dynamic>).remove('appaccount_password');
    return json;
  }

  void expectNoCredentialsInPreferences() {
    final json = storedUserJson();
    expect(json.containsKey('token'), isFalse);
    expect(
      (json['voip'] as Map<String, dynamic>).containsKey('appaccount_password'),
      isFalse,
    );
  }

  final testCredentials = Credentials(
    apiToken: testApiToken,
    sipPassword: testSipPassword,
  );

  setUp(() => api = MockNativeSecureStorage());

  test('Moves plain text credentials to secure storage on start', () async {
    final storage = await createStorage(
      preferenceValues: {'system_user': jsonEncode(testUser)},
    );

    verify(api.write(testCredentials));
    expectNoCredentialsInPreferences();
    expect(jsonEncode(storage.user), jsonEncode(testUser));
  });

  test('Keeps plain text credentials when they cannot be moved', () async {
    when(api.write(any)).thenThrow(PlatformException(code: 'keychain'));

    final storage = await createStorage(
      preferenceValues: {'system_user': jsonEncode(testUser)},
    );

    expect(storedUserJson()['token'], testApiToken);
    expect(jsonEncode(storage.user), jsonEncode(testUser));
  });

  test('Removes credentials left behind without a user', () async {
    await createStorage(credentials: testCredentials);

    verify(api.clear());
  });

  test('Reads credentials from secure storage', () async {
    final storage = await createStorage(
      preferenceValues: {
        'system_user': jsonEncode(userJsonWithoutCredentials()),
      },
      credentials: testCredentials,
    );

    verifyNever(api.write(any));
    verifyNever(api.clear());
    expect(jsonEncode(storage.user), jsonEncode(testUser));
  });

  test('Stores credentials in secure storage, not in preferences', () async {
    final storage = await createStorage();

    storage.user = testUser;
    await pumpEventQueue();

    expectNoCredentialsInPreferences();
    verify(api.write(testCredentials));
    expect(jsonEncode(storage.user), jsonEncode(testUser));
  });

  test('Does not write credentials that have not changed', () async {
    final storage = await createStorage(
      preferenceValues: {
        'system_user': jsonEncode(userJsonWithoutCredentials()),
      },
      credentials: testCredentials,
    );

    storage.user = testUser.copyWith(email: 'other@example.com');
    await pumpEventQueue();

    verifyNever(api.write(any));
  });

  test('A user without a token does not remove the stored one', () async {
    final storage = await createStorage(
      preferenceValues: {
        'system_user': jsonEncode(userJsonWithoutCredentials()),
      },
      credentials: Credentials(apiToken: testApiToken),
    );

    storage.user = User.fromJson(
      jsonDecode(jsonEncode(testUser)) as Map<String, dynamic>..remove('token'),
    );
    await pumpEventQueue();

    verify(api.write(Credentials(sipPassword: testSipPassword)));
    verifyNever(api.clear());
    expect(storage.user?.token, testApiToken);
  });

  test('Clearing removes secure storage and preferences', () async {
    final storage = await createStorage(
      preferenceValues: {
        'system_user': jsonEncode(userJsonWithoutCredentials()),
      },
      credentials: testCredentials,
    );

    await storage.clear();

    verify(api.clear());
    expect(preferences.getKeys(), isEmpty);
  });
}
