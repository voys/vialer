import 'package:flutter_test/flutter_test.dart';
import 'package:meta/meta.dart';
import 'package:vialer/presentation/features/main_page.dart';

import '../utils/test_extensions.dart';

/// Robots are a pattern that we use to encapsulate automated interactions with
/// our app. They provide human-readable methods to perform actions to make
/// tests easier to read and understand.
///
/// Requirements for implementing a robot:
/// - They should be grouped by feature (e.g. [CallingRobot])
/// - All robots should extend this base class
/// - Methods should be named so that test cases can be read like common speech
///
/// By default, robots verify they start from the home screen upon construction.
/// Override [startsFromHome] to disable this behavior if needed.
abstract class IntegrationTestRobot {
  IntegrationTestRobot(this.tester) {
    _performInitialChecks();
  }

  final WidgetTester tester;

  /// Controls whether the robot verifies it starts from the home screen upon
  /// construction. Defaults to true to catch issues where previous tests didn't
  /// properly clean up.
  ///
  /// Override and return false for robots that are specifically not designed to
  /// start from the home screen (but this shouldn't be common).
  bool get startsFromHome => true;

  void _performInitialChecks() {
    if (startsFromHome) {
      ensureOnHomeScreen();
    }
  }

  Future<void> goBack({int times = 1}) => tester.goBack(times: times);

  /// Verifies the app is on the home screen by checking that the bottom
  /// navigation bar can be interacted with, so nothing is pushed on top of it.
  ///
  /// Automatically called by the constructor when [startsFromHome] is true
  /// (default). You should not need to call this manually unless you want to
  /// re-verify the home screen state.
  @protected
  void ensureOnHomeScreen() {
    expect(
      find.byKey(MainPage.keys.navigationBar).hitTestable(),
      findsOneWidget,
      reason:
          'This test expects to start from the home screen, make sure the '
          'previous test returned home after it completed.',
    );
  }
}
