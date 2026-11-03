import 'package:flutter/services.dart';
import 'package:injectable/injectable.dart';

import '../../../presentation/util/pigeon.dart';

/// Credentials kept in the iOS Keychain or with the Android Keystore, shared
/// with native code.
///
/// They are read once at startup so they can be read synchronously.
@singleton
class SecureStorageRepository {
  SecureStorageRepository(this._api, this._credentials);

  @factoryMethod
  @preResolve
  static Future<SecureStorageRepository> create() async {
    final api = NativeSecureStorage();

    try {
      return SecureStorageRepository(api, await api.read());
    } on PlatformException {
      // The Keychain can't be read before the first unlock after a reboot, the
      // stored user can't be read then either.
      return SecureStorageRepository(api, Credentials());
    }
  }

  final NativeSecureStorage _api;
  Credentials _credentials;

  String? get apiToken => _credentials.apiToken;

  String? get sipPassword => _credentials.sipPassword;

  bool get isEmpty => apiToken == null && sipPassword == null;

  /// Values are available immediately. A `null` value is left as it is, so
  /// credentials that couldn't be read are never removed by accident, use
  /// [clear] for that.
  Future<void> write({String? apiToken, String? sipPassword}) async {
    final changed = Credentials(
      apiToken: apiToken != this.apiToken ? apiToken : null,
      sipPassword: sipPassword != this.sipPassword ? sipPassword : null,
    );
    if (changed.apiToken == null && changed.sipPassword == null) return;

    _credentials = Credentials(
      apiToken: apiToken ?? this.apiToken,
      sipPassword: sipPassword ?? this.sipPassword,
    );

    await _api.write(changed);
  }

  Future<void> clear() async {
    _credentials = Credentials();
    await _api.clear();
  }

  /// Where the Android Keystore key lives, `null` on iOS.
  Future<String?> keySecurityLevel() => _api.keySecurityLevel();
}
