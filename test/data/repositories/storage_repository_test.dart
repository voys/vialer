import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_secure_storage/shared_secure_storage.dart';
import 'package:vialer/data/models/user/user.dart';
import 'package:vialer/data/repositories/legacy/storage.dart';
import 'package:vialer/data/repositories/secure_storage/secure_storage_repository.dart';

@GenerateNiceMocks([MockSpec<SharedSecureStorage>()])
import 'storage_repository_test.mocks.dart';
import 'test_user.dart';

void main() {
  late SharedPreferences preferences;
  late MockSharedSecureStorage api;

  Future<StorageRepository> createStorage({
    Map<String, Object> preferenceValues = const {},
    String? apiToken,
    String? sipPassword,
  }) async {
    SharedPreferences.setMockInitialValues(preferenceValues);
    preferences = await SharedPreferences.getInstance();

    return StorageRepository.create(
      preferences,
      SecureStorageRepository(
        api,
        apiToken: apiToken,
        sipPassword: sipPassword,
      ),
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

  const keys = ['api_token', 'sip_password'];
  const testCredentials = {
    'api_token': testApiToken,
    'sip_password': testSipPassword,
  };

  setUp(() => api = MockSharedSecureStorage());

  test('Moves plain text credentials to secure storage on start', () async {
    final storage = await createStorage(
      preferenceValues: {'system_user': jsonEncode(testUser)},
    );

    verify(api.writeMany(testCredentials));
    expectNoCredentialsInPreferences();
    expect(jsonEncode(storage.user), jsonEncode(testUser));
  });

  test('Keeps plain text credentials when they cannot be moved', () async {
    when(api.writeMany(any)).thenThrow(PlatformException(code: 'keychain'));

    final storage = await createStorage(
      preferenceValues: {'system_user': jsonEncode(testUser)},
    );

    expect(storedUserJson()['token'], testApiToken);
    expect(jsonEncode(storage.user), jsonEncode(testUser));
  });

  test('Removes credentials left behind without a user', () async {
    await createStorage(
      apiToken: testApiToken,
      sipPassword: testSipPassword,
    );

    verify(api.deleteMany(keys));
  });

  test('Reads credentials from secure storage', () async {
    final storage = await createStorage(
      preferenceValues: {
        'system_user': jsonEncode(userJsonWithoutCredentials()),
      },
      apiToken: testApiToken,
      sipPassword: testSipPassword,
    );

    verifyNever(api.writeMany(any));
    verifyNever(api.deleteMany(any));
    expect(jsonEncode(storage.user), jsonEncode(testUser));
  });

  test('A stored user without a token counts as logged out', () async {
    final storage = await createStorage(
      preferenceValues: {
        'system_user': jsonEncode(userJsonWithoutCredentials()),
      },
    );

    expect(storage.user, isNull);
    // Nothing is removed, the token may only be unreadable for now.
    expect(preferences.containsKey('system_user'), isTrue);
  });

  test('Stores credentials in secure storage, not in preferences', () async {
    final storage = await createStorage();

    storage.user = testUser;
    await pumpEventQueue();

    expectNoCredentialsInPreferences();
    verify(api.writeMany(testCredentials));
    expect(jsonEncode(storage.user), jsonEncode(testUser));
  });

  test('Keeps credentials in preferences when storing them fails', () async {
    final storage = await createStorage();
    when(api.writeMany(any)).thenThrow(PlatformException(code: 'keystore'));

    storage.user = testUser;
    await pumpEventQueue();

    expect(storedUserJson()['token'], testApiToken);
    expect(
      (storedUserJson()['voip'] as Map<String, dynamic>)['appaccount_password'],
      testSipPassword,
    );
    expect(jsonEncode(storage.user), jsonEncode(testUser));
  });

  test(
    'Reloading picks up credentials that could not be read before',
    () async {
      when(api.readMany(any)).thenThrow(PlatformException(code: 'keychain'));
      SharedPreferences.setMockInitialValues({
        'system_user': jsonEncode(userJsonWithoutCredentials()),
      });
      preferences = await SharedPreferences.getInstance();
      final storage = await StorageRepository.create(
        preferences,
        await SecureStorageRepository.load(api),
      );

      expect(storage.user, isNull);

      when(api.readMany(any)).thenAnswer((_) async => testCredentials);
      await storage.reload();

      expect(jsonEncode(storage.user), jsonEncode(testUser));
    },
  );

  test('Reloading never drops credentials that are already known', () async {
    final storage = await createStorage(
      preferenceValues: {
        'system_user': jsonEncode(userJsonWithoutCredentials()),
      },
      apiToken: testApiToken,
      sipPassword: testSipPassword,
    );
    when(api.readMany(any)).thenAnswer((_) async => {});

    await storage.reload();

    expect(jsonEncode(storage.user), jsonEncode(testUser));
  });

  test('Does not write credentials that have not changed', () async {
    final storage = await createStorage(
      preferenceValues: {
        'system_user': jsonEncode(userJsonWithoutCredentials()),
      },
      apiToken: testApiToken,
      sipPassword: testSipPassword,
    );

    storage.user = testUser.copyWith(email: 'other@example.com');
    await pumpEventQueue();

    verifyNever(api.writeMany(any));
  });

  test('A user without a token does not remove the stored one', () async {
    final storage = await createStorage(
      preferenceValues: {
        'system_user': jsonEncode(userJsonWithoutCredentials()),
      },
      apiToken: testApiToken,
    );

    storage.user = User.fromJson(
      jsonDecode(jsonEncode(testUser)) as Map<String, dynamic>..remove('token'),
    );
    await pumpEventQueue();

    verify(api.writeMany({'sip_password': testSipPassword}));
    verifyNever(api.deleteMany(any));
    expect(storage.user?.token, testApiToken);
  });

  test('Clearing removes secure storage and preferences', () async {
    final storage = await createStorage(
      preferenceValues: {
        'system_user': jsonEncode(userJsonWithoutCredentials()),
      },
      apiToken: testApiToken,
      sipPassword: testSipPassword,
    );

    await storage.clear();

    verify(api.deleteMany(keys));
    expect(preferences.getKeys(), isEmpty);
  });
}
