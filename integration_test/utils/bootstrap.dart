import 'package:glog/glog.dart';
import 'package:integration_test/integration_test.dart';
import 'package:vialer/presentation/main.dart' as app;

Future<void> bootstrapAppForIntegrationTest() async {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // The resgate client prints every message it sends and receives, which
  // buries the test output. glog can only mute a context as a whole, so its
  // warnings and errors go as well.
  GlogLogger.global.mutedContexts.addAll(['res_client', 'res_model']);

  await app.main();
}
