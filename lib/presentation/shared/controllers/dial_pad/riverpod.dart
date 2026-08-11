import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:vialer/domain/usecases/clipboard/get_phone_number_from_clipboard.dart';
import 'package:vialer/domain/usecases/clipboard/has_phone_number_from_clipboard.dart';
import 'package:vialer/presentation/shared/controllers/dial_pad/state.dart';

part 'riverpod.g.dart';

@Riverpod(keepAlive: true)
class Clipboard extends _$Clipboard {
  late final _getPhoneNumberFromClipboardUseCase =
      GetPhoneNumberFromClipboardUseCase();
  late final _hasPhoneNumberFromClipboardUseCase =
      HasPhoneNumberFromClipboardUseCase();

  @override
  ClipboardState build() => const ClipboardState.initial();

  Future<void> getPhoneNumberFromClipboard() async {
    state = const ClipboardState.loading();
    final number = await _getPhoneNumberFromClipboardUseCase();
    state = number != null
        ? ClipboardState.success(number)
        : const ClipboardState.unavailable();
  }

  Future<void> hasPhoneNumberFromClipboard() =>
      _hasPhoneNumberFromClipboardUseCase().then((hasPhoneNumber) {
        state = hasPhoneNumber
            ? const ClipboardState.hasPhoneNumber()
            : const ClipboardState.unavailable();
      });
}
