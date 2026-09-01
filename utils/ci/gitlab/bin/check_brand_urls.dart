// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

const _urlKeys = ['supportUrl', 'supportUrlNL', 'privacyPolicyUrl'];

Future<void> main() async {
  // Some sites reject requests without a browser-like user agent.
  final client = HttpClient()..userAgent = 'Mozilla/5.0';
  final passed = <String>[];
  final failed = <String>[];

  for (final file in Directory('brands').listSync().whereType<File>()) {
    if (!file.path.endsWith('.json')) continue;

    final config = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    final brand = config['identifier'];

    for (final key in _urlKeys) {
      final url = config[key] as String? ?? '';
      if (url.isEmpty) continue;

      try {
        final request = await client.getUrl(Uri.parse(url));
        final response = await request.close().timeout(
          const Duration(seconds: 30),
        );
        await response.drain<void>();

        if (response.statusCode >= 400) {
          failed.add('❌ [$brand] $key: $url (HTTP ${response.statusCode})');
        } else {
          passed.add('✅ [$brand] $key: $url');
        }
      } on Exception catch (error) {
        failed.add('❌ [$brand] $key: $url ($error)');
      }
    }
  }

  client.close();

  print('\nPassed (${passed.length}):');
  passed.forEach(print);

  print('\nFailed (${failed.length}):');
  failed.forEach(print);

  if (failed.isNotEmpty) exit(1);
}
