import '../vialer.dart';

class NeedToChangePasswordException extends VialerException {}

class FailedToRetrieveUserException extends VialerException {
  FailedToRetrieveUserException({
    this.statusCode,
    this.error,
  });
  int? statusCode;
  String? error;

  @override
  String toString() =>
      'FailedToRetrieveUserException: $error with error code: $statusCode';
}
