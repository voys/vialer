import '../../../data/repositories/legacy/storage.dart';
import '../../../dependency_locator.dart';
import '../authentication/is_authenticated.dart';
import '../authentication/logout.dart';
import '../use_case.dart';

/// If the User is ever in a state where they have starting logging in but
/// didn't finish onboarding, we want to log them out.
class LogoutOnIncompleteOnboarding extends UseCase {
  late final _isAuthenticated = IsAuthenticated();
  late final _logout = Logout();
  late final _storageRepository = dependencyLocator<StorageRepository>();

  Future<void> call() async {
    if (_isAuthenticatedButDidNotCompleteOnboarding) {
      _logout();
    }
  }

  bool get _isAuthenticatedButDidNotCompleteOnboarding =>
      _isAuthenticated() && !_storageRepository.hasCompletedOnboarding;
}
