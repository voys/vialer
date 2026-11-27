import 'dart:async';

import '../../../data/models/event/event_bus.dart';
import '../../../data/repositories/legacy/storage.dart';
import '../../../dependency_locator.dart';
import '../../../presentation/util/synchronized_task.dart';
import '../calling/voip/stop_voip.dart';
import '../use_case.dart';
import '../user/get_stored_user.dart';
import '../user/settings/clear_and_preserve_cross_session_settings.dart';
import 'user_was_logged_out.dart';

class Logout extends UseCase {
  final _storageRepository = dependencyLocator<StorageRepository>();
  final _eventBus = dependencyLocator<EventBus>();

  final _getUser = GetStoredUserUseCase();
  final _stopVoip = StopVoipUseCase();
  final _preserveCrossSessionSettings =
      ClearStorageAndPreserveCrossSessionSettings();

  Future<void> call() async {
    await _stopVoip();

    // Queued with user refreshes and setting changes, so those already waiting
    // finish first instead of storing values after the storage is cleared.
    final loggedOut = await SynchronizedTask<bool>.named(
      userSettingsTask,
      SynchronizedTaskMode.queue,
    ).run(_clearStorage);

    if (loggedOut) _eventBus.broadcast(const UserWasLoggedOutEvent());
  }

  /// Clear the storage of all user-specific values.
  ///
  /// Returns false if another logout got there first.
  Future<bool> _clearStorage() async {
    final user = _getUser();
    if (user == null) return false;

    final pushToken = _storageRepository.pushToken;
    final remoteNotificationToken = _storageRepository.remoteNotificationToken;

    await _preserveCrossSessionSettings(user);

    _storageRepository
      ..pushToken = pushToken
      ..remoteNotificationToken = remoteNotificationToken;

    return true;
  }
}
