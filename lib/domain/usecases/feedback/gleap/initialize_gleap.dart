import 'package:dartx/dartx.dart';
import 'package:gleap_sdk/gleap_sdk.dart';

import '../../../../data/repositories/env.dart';
import '../../../../dependency_locator.dart';
import '../../use_case.dart';
import '../../user/get_brand.dart';
import '../../user/get_stored_user.dart';
import 'gleap_state.dart';
import 'identify_gleap_user.dart';

class InitializeGleap extends UseCase {
  final _envRepository = dependencyLocator<EnvRepository>();
  final _getStoredUser = GetStoredUserUseCase();
  final _identifyGleapUser = IdentifyGleapUser();
  final _getBrand = GetBrand();

  bool get isAvailable {
    final brand = _getBrand();

    return _envRepository.gleapApiKey.isNotBlank &&
        (brand.isVoys || brand.isVialer);
  }

  Future<void> call() async {
    if (GleapState.isInitialized || !isAvailable) return;

    try {
      await Gleap.initialize(token: _envRepository.gleapApiKey);

      await Gleap.showFeedbackButton(false);

      GleapState.isInitialized = true;

      final user = _getStoredUser();
      if (user != null) {
        await _identifyGleapUser(user);
      }
    } on Exception catch (exception) {
      logger.warning('Could not initialize Gleap', exception);
    }
  }
}
