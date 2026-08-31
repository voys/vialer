import 'package:dartx/dartx.dart';
import 'package:gleap_sdk/gleap_sdk.dart';

import '../../../../data/repositories/env.dart';
import '../../../../dependency_locator.dart';
import '../../use_case.dart';
import '../../user/get_brand.dart';

/// Safe to call multiple times, initialization will only ever happen once.
class InitializeGleap extends UseCase {
  final _envRepository = dependencyLocator<EnvRepository>();
  final _getBrand = GetBrand();

  /// The Gleap SDK doesn't expose whether it has been initialized, so we
  /// keep the pending initialization around to guarantee it only runs once.
  static Future<void>? _initialization;

  bool get isAvailable {
    final brand = _getBrand();

    return _envRepository.gleapApiKey.isNotBlank &&
        (brand.isVoys || brand.isVialer);
  }

  Future<void> call() async {
    if (!isAvailable) return;

    return _initialization ??= _initialize();
  }

  Future<void> _initialize() async {
    try {
      await Gleap.initialize(token: _envRepository.gleapApiKey);
      await Gleap.showFeedbackButton(false);
    } on Exception catch (exception) {
      _initialization = null;
      logger.warning('Could not initialize Gleap', exception);
    }
  }
}
