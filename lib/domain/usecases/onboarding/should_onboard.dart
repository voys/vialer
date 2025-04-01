import '../authentication/is_authenticated.dart';
import '../use_case.dart';

/// Returns `true` if we should start onboarding.
class ShouldOnboard extends UseCase {
  final _isAuthenticated = IsAuthenticated();

  bool call() => !_isAuthenticated();
}
