import 'package:injectable/injectable.dart';
import 'package:vialer/domain/usecases/calling/voip/unregister_to_middleware.dart';
import 'package:vialer/global.dart';

import '../../../../data/repositories/legacy/storage.dart';
import '../../../../presentation/util/pigeon.dart';
import '../../authentication/get_is_logged_in_somewhere_else.dart';
import '../../use_case.dart';
import '../../user/get_logged_in_user.dart';
import 'get_has_voip_enabled.dart';

@injectable
class RegisterToMiddlewareUseCase extends UseCase {
  RegisterToMiddlewareUseCase(this._storageRepository);
  final StorageRepository _storageRepository;

  final _getHasVoipEnabled = GetHasVoipEnabledUseCase();
  final _isLoggedInSomewhereElse = GetIsLoggedInSomewhereElseUseCase();
  final _unregisterToMiddleware = UnregisterToMiddlewareUseCase();
  final _getUser = GetLoggedInUserUseCase();

  final _middleware = MiddlewareRegistrar();

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
      _middleware.register(_storageRepository.pushToken!);
    } else {
      _trackNotPossible('voip-not-enabled');
    }
  }

  void _trackNotPossible(String event) =>
      track('middleware-registration-not-possible-$event');
}
