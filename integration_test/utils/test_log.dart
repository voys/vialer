import 'package:flutter/foundation.dart';

/// Logs what the integration tests do and with which data, so a run's output
/// reads as a list of what was tested. Never log a password.
abstract final class TestLog {
  static const _divider = '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';

  static final _run = Stopwatch();
  static var _passed = 0;
  static var _skipped = 0;

  static void start() {
    _run.start();
    debugPrint('🧪 Starting the integration tests');
  }

  static void finish() => debugPrint(
    '\n🏁 $_passed tests passed, $_skipped skipped, in '
    '${_formatDuration(_run.elapsed)}',
  );

  /// Heads the tests of one feature.
  static void group(String emoji, String name) =>
      debugPrint('\n$_divider\n$emoji $name\n$_divider');

  /// Runs [body] as one test, logging when it starts, passes or fails.
  static Future<void> test(
    String description,
    Future<void> Function() body,
  ) async {
    debugPrint('\n▶️  $description');
    final stopwatch = Stopwatch()..start();

    try {
      await body();
    } catch (_) {
      debugPrint(
        '❌ $description, failed after ${_formatDuration(stopwatch.elapsed)}',
      );
      rethrow;
    }

    _passed++;
    debugPrint('✅ $description (${_formatDuration(stopwatch.elapsed)})');
  }

  /// A piece of data the current test uses, such as the number it dials.
  static void detail(String label, Object? value) =>
      debugPrint('   • $label: ${value ?? '(none)'}');

  /// Something the test does that is worth following along with.
  static void step(String emoji, String message) =>
      debugPrint('   $emoji $message');

  static void skip(String description, {required String because}) {
    _skipped++;
    debugPrint('\n⏭️  $description, skipped: $because');
  }

  static void warning(String message) => debugPrint('   ⚠️  $message');

  static String _formatDuration(Duration duration) {
    if (duration.inMinutes == 0) {
      return '${(duration.inMilliseconds / 1000).toStringAsFixed(1)}s';
    }
    return '${duration.inMinutes}m ${duration.inSeconds % 60}s';
  }
}
