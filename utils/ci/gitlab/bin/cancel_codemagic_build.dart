// ignore_for_file: avoid_print

import 'dart:io';

import '../../ci_utils.dart';

Future<void> main() async {
  final buildIdFile = File(codemagicBuildIdFile);
  final env = Platform.environment;

  if (env['CI_JOB_STATUS'] == 'success') {
    print('${ansiGreen}Codemagic build passed, nothing to cancel.$ansiReset');
    return;
  }

  if (!buildIdFile.existsSync()) {
    print('No Codemagic build was started, nothing to cancel.');
    return;
  }

  final buildId = buildIdFile.readAsStringSync().trim();
  final request = await HttpClient().postUrl(
    Uri.parse('https://api.codemagic.io/builds/$buildId/cancel'),
  );
  request.headers.set('x-auth-token', env['CODEMAGIC_API_TOKEN'] ?? '');
  final response = await request.close();
  final body = await readResponse(response);

  if (response.statusCode == HttpStatus.ok) {
    print('');
    printBox(
      [
        '✗ Cancelled the Codemagic build',
        codemagicBuildUrl(env['CODEMAGIC_APP_ID'] ?? '', buildId),
      ],
      color: ansiRed,
      titleStyle: '$ansiBold$ansiRed',
    );
  } else {
    print(
      'Codemagic build $buildId was not cancelled '
      '(HTTP ${response.statusCode}): $body',
    );
  }
}
