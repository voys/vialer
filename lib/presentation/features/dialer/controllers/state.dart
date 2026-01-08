import 'package:freezed_annotation/freezed_annotation.dart';

part 'state.freezed.dart';

@freezed
abstract class DialerState with _$DialerState {
  const factory DialerState({String? lastCalledDestination}) = _DialerState;
}
