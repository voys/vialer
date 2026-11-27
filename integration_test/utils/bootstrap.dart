import 'package:flutter/foundation.dart';
import 'package:glog/glog.dart';
import 'package:integration_test/integration_test.dart';
import 'package:logging/logging.dart';
import 'package:vialer/presentation/main.dart' as app;

Future<void> bootstrapAppForIntegrationTest() async {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // The resgate client prints every message it sends and receives, which
  // buries the test output. glog can only mute a context as a whole, so its
  // warnings and errors go as well.
  GlogLogger.global.mutedContexts.addAll(['res_client', 'res_model']);

  // The app logs through dart:developer, which only reaches an attached
  // debugger. Remote runners such as emulator.wtf only collect logcat, so the
  // app's logs are printed as well to end up next to the test output.
  Logger.root.onRecord.listen(
    (record) => debugPrint(
      '📋 ${record.level.name} ${record.loggerName}: ${record.message}'
      '${record.error != null ? ' (${record.error})' : ''}',
    ),
  );

  await app.main();
}
