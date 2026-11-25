// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io' show ContentType, HttpClient, Platform, exit;

import '../../ci_utils.dart';

Future<void> main(List<String> args) async {
  final env = Platform.environment;

  final mergeRequestId = env['CI_MERGE_REQUEST_IID'];
  final apiToken = env['GITLAB_API_TOKEN'];
  final url = Uri.parse(
    'https://gitlab.wearespindle.com/api/v4/projects/105/merge_requests/$mergeRequestId',
  );

  if (apiToken == null) {
    print('GITLAB_API_TOKEN not found.');
    exit(1);
  }

  final client = HttpClient();
  var request = await client.getUrl(url);
  request.headers.contentType = ContentType.json;
  request.headers.set('Private-Token', apiToken);

  var response = await request.close();

  print('Request MR description.');
  if (response.statusCode != 200) {
    print('Response code: ${response.statusCode}.');
    print(await readResponse(response));
    exit(1);
  }

  final body = jsonDecode(await readResponse(response)) as Map<String, dynamic>;
  final description = body['description'] as String;

  if (description.containsCodemagicLink) {
    print('Previous build information found, updating MR description..');

    request = await client.putUrl(url);
    request.headers.contentType = ContentType.json;
    request.headers.set('Private-Token', apiToken);
    request.write(
      jsonEncode({'description': description.withoutCodemagicLink}),
    );
    response = await request.close();

    if (response.statusCode == 200) {
      print('Updated MR description.');
    } else {
      print('Response code: ${response.statusCode}.');
      print(await readResponse(response));
      exit(1);
    }
  } else {
    print('No build information found, so not updating MR description.');
  }

  exit(0);
}

const _codemagicLinkLineStart = '[Codemagic: Latest Build';

extension CodemagicStringExtension on String {
  bool get containsCodemagicLink => contains(_codemagicLinkLineStart);

  String get withoutCodemagicLink => const LineSplitter()
      .convert(this)
      .where((line) => !line.startsWith(_codemagicLinkLineStart))
      .join('\n');
}
