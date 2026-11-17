import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:injectable/injectable.dart';
import 'package:shared_secure_storage/shared_secure_storage.dart';

/// Credentials kept in the iOS Keychain or with the Android Keystore, shared
/// with native code.
///
/// They are read once at startup so they can be read synchronously.
@singleton
class SecureStorageRepository {
  SecureStorageRepository(
    this._storage, {
    String? apiToken,
    String? sipPassword,
  }) : _apiToken = apiToken,
       _sipPassword = sipPassword;

  @factoryMethod
  @preResolve
  static Future<SecureStorageRepository> create() =>
      load(SharedSecureStorage());

  @visibleForTesting
  static Future<SecureStorageRepository> load(
    SharedSecureStorage storage,
  ) async {
    final repository = SecureStorageRepository(storage);
    await repository.reload();
    return repository;
  }

  /// Reads the credentials again. They can't be read before the first unlock
  /// after a restart, just like the stored user.
  ///
  /// This only ever adds what was missing. A value that can't be read right
  /// now never replaces one that is already known, otherwise a temporary
  /// failure would log the user out.
  Future<void> reload() async {
    try {
      final values = await _storage.readMany([_apiTokenKey, _sipPasswordKey]);

      _apiToken ??= values[_apiTokenKey];
      _sipPassword ??= values[_sipPasswordKey];
    } on PlatformException {
      // Tried again on the next reload.
    }
  }

  /// Native code reads the token with the same key, see `Middleware.kt` and
  /// `Middleware.swift`.
  static const _apiTokenKey = 'api_token';
  static const _sipPasswordKey = 'sip_password';

  final SharedSecureStorage _storage;
  String? _apiToken;
  String? _sipPassword;

  String? get apiToken => _apiToken;

  String? get sipPassword => _sipPassword;

  bool get isEmpty => apiToken == null && sipPassword == null;

  /// Values are available immediately. A `null` value is left as it is, so
  /// credentials that couldn't be read are never removed by accident, use
  /// [clear] for that.
  Future<void> write({String? apiToken, String? sipPassword}) async {
    final changed = {
      if (apiToken != null && apiToken != _apiToken) _apiTokenKey: apiToken,
      if (sipPassword != null && sipPassword != _sipPassword)
        _sipPasswordKey: sipPassword,
    };
    if (changed.isEmpty) return;

    _apiToken = apiToken ?? _apiToken;
    _sipPassword = sipPassword ?? _sipPassword;

    await _storage.writeMany(changed);
  }

  Future<void> clear() async {
    _apiToken = null;
    _sipPassword = null;
    await _storage.deleteMany([_apiTokenKey, _sipPasswordKey]);
  }

  /// Where the Android Keystore key lives, `null` on iOS.
  Future<String?> keySecurityLevel() => _storage.keySecurityLevel();
}
