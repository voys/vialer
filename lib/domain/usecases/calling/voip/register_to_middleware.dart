import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:injectable/injectable.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:vialer/domain/usecases/calling/voip/unregister_to_middleware.dart';
import 'package:vialer/global.dart';

import '../../../../data/repositories/legacy/storage.dart';
import '../../../../presentation/util/pigeon.dart';
import '../../authentication/get_is_logged_in_somewhere_else.dart';
import '../../use_case.dart';
import '../../user/get_brand.dart';
import '../../user/get_logged_in_user.dart';
import 'get_has_voip_enabled.dart';

@injectable
class RegisterToMiddlewareUseCase extends UseCase {
  final StorageRepository _storageRepository;

  final _getHasVoipEnabled = GetHasVoipEnabledUseCase();
  final _isLoggedInSomewhereElse = GetIsLoggedInSomewhereElseUseCase();
  final _unregisterToMiddleware = UnregisterToMiddlewareUseCase();
  final _getUser = GetLoggedInUserUseCase();

  final _middleware = MiddlewareRegistrar();

  RegisterToMiddlewareUseCase(this._storageRepository);

  Future<void> call() async {
    if (await _isLoggedInSomewhereElse()) {
      _unregisterToMiddleware();
      logger.info('Registration cancelled: User has logged in elsewhere');
      return;
    }

    if (_getUser().appAccount?.sipUserId == null) {
      _trackNotPossible('no-sip-user-id');
      logger.info('Registration cancelled: No SIP user ID set');
      return;
    }

    if (_storageRepository.pushToken == null) {
      _trackNotPossible('no-token');
      logger.info('Registration cancelled: No token');
      return;
    }

    if (_getHasVoipEnabled()) {
      logger.info('Register to middleware natively');
      await _unregisterFromLegacyMiddleware();
      _middleware.register(_storageRepository.pushToken!);
    } else {
      _trackNotPossible('voip-not-enabled');
    }
  }

  Future<void> _unregisterFromLegacyMiddleware() async {
    final user = _getUser();
    final token = user.token;
    final sipUserId = user.appAccount?.sipUserId;
    final pushToken = _storageRepository.pushToken;

    if (token == null ||
        sipUserId == null ||
        sipUserId.isEmpty ||
        pushToken == null) {
      return;
    }

    final environment =
        GetBrand()().identifier == 'vialerStaging' ? 'staging' : 'production';
    final device = Platform.isAndroid ? 'android-device' : 'apns-device';
    final url =
        Uri.parse('https://vmex.eu-$environment.holodeck.voys.nl/api/$device');

    try {
      final app = (await PackageInfo.fromPlatform()).packageName;

      final response = await http.delete(
        url,
        headers: {'Authorization': 'Token ${user.email}:$token'},
        body: {'token': pushToken, 'sip_user_id': sipUserId, 'app': app},
      );

      logger.info(
        'Legacy middleware unregister responded: ${response.statusCode}',
      );
    } catch (e) {
      logger.warning('Legacy middleware unregister failed: $e');
    }
  }

  void _trackNotPossible(String event) =>
      track('middleware-registration-not-possible-$event');
}
