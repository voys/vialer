import 'dart:async';

import '../../../data/repositories/legacy/storage.dart';
import '../../../dependency_locator.dart';
import '../feedback/gleap/identify_gleap_user.dart';
import '../use_case.dart';
import '../user/get_stored_user.dart';
import 'identify_for_tracking.dart';

class PeriodicallyIdentifyForTracking extends UseCase {
  final _storageRepository = dependencyLocator<StorageRepository>();
  final _identifyForMetrics = IdentifyForTrackingUseCase();
  final _identifyGleapUser = IdentifyGleapUser();
  final _getUser = GetStoredUserUseCase();

  Future<void> call() async {
    final lastIdentifyTime = _storageRepository.lastPeriodicIdentifyTime;

    // We don't want to do anything if there's no logged in user yet.
    if (_getUser() == null) return;

    if (lastIdentifyTime.isReadyForTracking) {
      _storageRepository.lastPeriodicIdentifyTime = DateTime.now();
      unawaited(_identifyGleapUser());
      return _identifyForMetrics();
    }
  }
}

extension on DateTime? {
  /// The minimum period between when we automatically identify for metrics,
  /// this does not mean there can't be other identify calls if other actions
  /// occur that would trigger it.
  static const _minPeriod = Duration(days: 1);

  bool get isReadyForTracking =>
      this?.isBefore(DateTime.now().subtract(_minPeriod)) ?? true;
}
