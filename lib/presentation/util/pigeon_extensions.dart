import 'package:vialer/presentation/util/pigeon.dart';

class _NativeToFlutterListener implements NativeToFlutter {
  _NativeToFlutterListener({required this.onLaunchDialerAndPopulateNumber});
  final void Function(String) onLaunchDialerAndPopulateNumber;

  @override
  Future<void> launchDialerAndPopulateNumber(String number) async =>
      onLaunchDialerAndPopulateNumber(number);
}

extension NativeToFlutterSetup on NativeToFlutter {
  static void onLaunchDialerAndPopulateNumber(void Function(String) callback) =>
      NativeToFlutter.setUp(
        _NativeToFlutterListener(onLaunchDialerAndPopulateNumber: callback),
      );
}
