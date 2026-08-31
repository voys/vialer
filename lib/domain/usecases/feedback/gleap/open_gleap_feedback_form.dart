import 'package:dartx/dartx.dart';
import 'package:gleap_sdk/gleap_sdk.dart';

import '../../../../data/repositories/env.dart';
import '../../../../data/repositories/metrics/metrics.dart';
import '../../../../dependency_locator.dart';
import '../../use_case.dart';
import 'gleap_state.dart';
import 'initialize_gleap.dart';

class OpenGleapFeedbackForm extends UseCase {
  final _envRepository = dependencyLocator<EnvRepository>();
  final _metricsRepository = dependencyLocator<MetricsRepository>();
  final _initializeGleap = InitializeGleap();

  bool get isAvailable => _initializeGleap.isAvailable;

  Future<void> call() async {
    await _initializeGleap();

    if (!GleapState.isInitialized) return;

    final formId = _envRepository.gleapFormId;

    try {
      if (formId.isNotBlank) {
        await Gleap.startClassicForm(formId: formId);
      } else {
        await Gleap.open();
      }

      _metricsRepository.track('gleap-feedback-form-opened', {
        'formId': formId.isNotBlank ? formId : 'widget',
      });
    } on Exception catch (exception) {
      logger.warning('Could not open Gleap feedback form', exception);
    }
  }
}
