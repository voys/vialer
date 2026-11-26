import 'package:integration_test/integration_test.dart';
import 'package:vialer/presentation/main.dart' as app;

Future<void> bootstrapAppForIntegrationTest() async {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  await app.main();
}
