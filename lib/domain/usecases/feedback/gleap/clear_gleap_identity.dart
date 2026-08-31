import 'package:gleap_sdk/gleap_sdk.dart';

import '../../use_case.dart';
import 'initialize_gleap.dart';

class ClearGleapIdentity extends UseCase {
  final _initializeGleap = InitializeGleap();

  Future<void> call() async {
    if (!_initializeGleap.isAvailable) return;

    await _initializeGleap();

    try {
      await Gleap.clearIdentity();
    } on Exception catch (exception) {
      logger.warning('Could not clear Gleap identity', exception);
    }
  }
}
