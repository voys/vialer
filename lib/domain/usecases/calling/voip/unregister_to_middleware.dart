import 'package:vialer/presentation/util/pigeon.dart';

import '../../../../data/models/voipgrid/app_account.dart';
import '../../use_case.dart';
import '../../user/get_logged_in_user.dart';

class UnregisterToMiddlewareUseCase extends UseCase {
  final _middleware = MiddlewareRegistrar();
  final _getUser = GetLoggedInUserUseCase();

  Future<void> call({AppAccount? appAccount}) async {
    final user = _getUser();

    if (appAccount != null || user.isAllowedVoipCalling) {
      final appAccountId = int.tryParse(
        (appAccount ?? user.appAccount).sipUserId,
      );
      if (appAccountId == null) return;

      await _middleware.unregister(appAccountId);
    }
  }
}
