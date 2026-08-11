// ignore_for_file: unused_element
// ignore_for_file: unused_element_parameter
import 'package:dartx/dartx.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:injectable/injectable.dart' hide Module;
import 'package:vialer/data/API/voipgrid/voipgrid_service.dart';

import '../../../../presentation/util/loggable.dart';
import '../../../models/calling/voip/destination.dart';

part 'user_details.freezed.dart';
part 'user_details.g.dart';

@injectable
class UserDetailsRepository with Loggable {
  UserDetailsRepository(this._service);

  final VoipgridService _service;

  Future<UserDetails?> getUserDetails() async {
    final response = await _service.getUserDetails();

    if (!response.isSuccessful) {
      logFailedResponse(response, name: 'Get User Details');
      return null;
    }

    return UserDetails.fromJson(response.body!);
  }
}

@Freezed(toJson: false)
abstract class UserDetails with _$UserDetails {
  @JsonSerializable(fieldRename: FieldRename.snake, createToJson: false)
  const factory UserDetails({
    required String firstName,
    required String lastName,
    required String internalNumber,
    required _Destinations destinations,
    String? preposition,
    _SelectedDestination? selectedDestination,
    _AppAccount? app,
    _WebphoneAccount? webphone,
    _ClientDetails? client,
  }) = _UserDetails;
  const UserDetails._();

  factory UserDetails.fromJson(Map<String, dynamic> json) =>
      _$UserDetailsFromJson(json);

  List<Destination> get availableDestinations => [
    ...destinations.fixedDestinations,
    ...destinations.voipAccounts,
  ].map((e) => e.toDestination()).toList();
}

@Freezed(toJson: false, fromJson: false)
abstract class _ClientDetails with _$ClientDetails {
  @JsonSerializable(fieldRename: FieldRename.snake, createToJson: false)
  const factory _ClientDetails({
    _ClientModules? modules,
  }) = __ClientDetails;

  factory _ClientDetails.fromJson(Map<String, dynamic> json) =>
      _$ClientDetailsFromJson(json);
}

@Freezed(toJson: false, fromJson: false)
abstract class _ClientModules with _$ClientModules {
  @JsonSerializable(fieldRename: FieldRename.snake, createToJson: false)
  const factory _ClientModules({
    @Default(false) bool callrecording,
    _IntelligenceModules? intelligence,
  }) = __ClientModules;

  factory _ClientModules.fromJson(Map<String, dynamic> json) =>
      _$ClientModulesFromJson(json);
}

@Freezed(toJson: false, fromJson: false)
abstract class _IntelligenceModules with _$IntelligenceModules {
  @JsonSerializable(fieldRename: FieldRename.snake, createToJson: false)
  const factory _IntelligenceModules({
    @Default(false) bool transcribeCallrecordings,
    @Default(false) bool summarizeCallTranscriptions,
  }) = __IntelligenceModules;

  factory _IntelligenceModules.fromJson(Map<String, dynamic> json) =>
      _$IntelligenceModulesFromJson(json);
}

@Freezed(toJson: false, fromJson: false)
abstract class _AppAccount with _$AppAccount {
  @JsonSerializable(fieldRename: FieldRename.snake)
  const factory _AppAccount({
    required bool useMobileNumberAsFallback,
    String? mobileNumber,
    _VoipAccountDestination? voipAccount,
  }) = __AppAccount;

  factory _AppAccount.fromJson(Map<String, dynamic> json) =>
      _$AppAccountFromJson(json);
}

@Freezed(toJson: false, fromJson: false)
abstract class _WebphoneAccount with _$WebphoneAccount {
  @JsonSerializable(fieldRename: FieldRename.snake)
  const factory _WebphoneAccount({
    _VoipAccountDestination? voipAccount,
  }) = __WebphoneAccount;

  factory _WebphoneAccount.fromJson(Map<String, dynamic> json) =>
      _$WebphoneAccountFromJson(json);
}

@Freezed(toJson: false, fromJson: false)
abstract class _Destinations with _$Destinations {
  @JsonSerializable(fieldRename: FieldRename.snake)
  const factory _Destinations({
    @Default([]) Iterable<_VoipAccountDestination> voipAccounts,
    @Default([]) Iterable<_FixedDestination> fixedDestinations,
  }) = __Destinations;

  factory _Destinations.fromJson(Map<String, dynamic> json) =>
      _$DestinationsFromJson(json);
}

@freezed
sealed class _Destination with _$Destination {
  factory _Destination.fromJson(Map<String, dynamic> json) =>
      _$DestinationFromJson(json);
  const _Destination._();

  @JsonSerializable(fieldRename: FieldRename.snake)
  const factory _Destination.voipAccount({
    required String id,
    required String uuid,
    required String accountId,
    required String description,
    required String internalNumber,
    required String status,
  }) = _VoipAccountDestination;

  @JsonSerializable(fieldRename: FieldRename.snake)
  const factory _Destination.fixed({
    required String id,
    required String uuid,
    required String phoneNumber,
    required String description,
  }) = _FixedDestination;

  Destination toDestination() => map(
    voipAccount: (voipAccount) => Destination.phoneAccount(
      voipAccount.id.toInt(),
      voipAccount.description,
      voipAccount.accountId.toInt(),
      voipAccount.internalNumber.toInt(),
    ),
    fixed: (fixed) => Destination.phoneNumber(
      fixed.id.toInt(),
      fixed.description,
      fixed.phoneNumber,
    ),
  );
}

@Freezed(toJson: false, fromJson: false)
abstract class _SelectedDestination with _$SelectedDestination {
  @JsonSerializable(fieldRename: FieldRename.snake)
  const factory _SelectedDestination({
    required String id,
    required String uuid,
    _VoipAccountDestination? voipAccount,
    _FixedDestination? fixedDestination,
  }) = __SelectedDestination;

  factory _SelectedDestination.fromJson(Map<String, dynamic> json) =>
      _$SelectedDestinationFromJson(json);
  const _SelectedDestination._();

  Destination? asDestination() => [
    voipAccount,
    fixedDestination,
  ].filterNotNull().firstOrNull?.toDestination();
}
