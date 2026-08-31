import 'package:gleap_sdk/gleap_sdk.dart';

import '../../use_case.dart';
import 'gleap_state.dart';

class ClearGleapIdentity extends UseCase {
  Future<void> call() async {
    if (!GleapState.isInitialized) return;

    try {
      await Gleap.clearIdentity();
    } on Exception catch (exception) {
      logger.warning('Could not clear Gleap identity', exception);
    }
  }
}
