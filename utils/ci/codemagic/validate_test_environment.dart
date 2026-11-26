// ignore_for_file: avoid_print
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// Checks that the integration test user can still log in before a long test
/// run is started, so an expired password or a VoIPGRID outage fails fast with
/// a clear message instead of somewhere inside the suite.
///
/// Reads the credentials from the environment, as Codemagic provides them.
final _username =
    Platform.environment['INTEGRATION_TEST_USER_1_USERNAME'] ?? '';
final _password =
    Platform.environment['INTEGRATION_TEST_USER_1_PASSWORD'] ?? '';
final _brand = Platform.environment['BRAND'] ?? 'vialer';

final _slackWebhookUrl =
    Platform.environment['TEST_ENVIRONMENT_SLACK_WEBHOOK_URL'];

/// Every request is given this long to produce a response, so a hanging server
/// fails the validation with a clear message instead of a transport error
/// (e.g. `Connection closed before full header was received`) once an
/// intermediate proxy drops the connection.
const _requestTimeout = Duration(seconds: 15);

Map<String, String> get _jsonHeaders => {'Content-Type': 'application/json'};

Future<void> main() async {
  print('🔍 Validating test environment...\n');

  try {
    print('🔐 Using test credentials:');
    print('   Username: $_username');
    print('   Password: ${_password.masked}\n');

    _validateCredentials();

    final token = await _getAuthToken(_voipgridUrl());
    await _validateToken(_voipgridUrl(), token);

    print('✅ Test environment validation successful!');
    print(
      '🚀 Environment is properly configured and ready for integration tests\n',
    );

    exit(0);
  } catch (e, stackTrace) {
    stderr.writeln('❌ Test environment validation failed: $e');
    await _notifySlackFailure(e, stackTrace);
    exit(1);
  }
}

String _voipgridUrl() {
  final brand =
      jsonDecode(File('brands/$_brand.json').readAsStringSync())
          as Map<String, dynamic>;
  return brand['voipgridUrl'] as String;
}

void _validateCredentials() {
  if (_username.isEmpty || _password.isEmpty) {
    throw Exception(
      'Integration test credentials not found. '
      'Please ensure INTEGRATION_TEST_USER_1_USERNAME and '
      'INTEGRATION_TEST_USER_1_PASSWORD are set in the environment',
    );
  }
}

Future<http.Response> _send(
  String description,
  Future<http.Response> Function() send,
) async {
  try {
    return await send().timeout(_requestTimeout);
  } on TimeoutException {
    throw Exception(
      '$description timed out after ${_requestTimeout.inSeconds}s: '
      'the server accepted the request but never responded.',
    );
  } on http.ClientException catch (e) {
    throw Exception('$description could not be completed: ${e.message}');
  } on SocketException catch (e) {
    throw Exception('$description could not reach the server: ${e.message}');
  }
}

Future<String> _getAuthToken(String voipgridUrl) async {
  print('🔐 Logging in to VoIPGRID ($voipgridUrl)...');

  final response = await _send(
    'VoIPGRID login',
    () => http.post(
      Uri.parse('$voipgridUrl/api/permission/apitoken/'),
      headers: _jsonHeaders,
      body: jsonEncode({'email': _username, 'password': _password}),
    ),
  );

  if (!response.isSuccess) {
    throw Exception(
      'Authentication failed: ${response.statusCode} ${response.body}',
    );
  }

  final token =
      (jsonDecode(response.body) as Map<String, dynamic>)['api_token']
          as String;

  print('   ✓ Logged in successfully');
  print('   Token: ${token.masked}\n');

  return token;
}

Future<void> _validateToken(String voipgridUrl, String token) async {
  print('👤 Fetching the user details...');

  final response = await _send(
    'Fetching the user details',
    () => http.get(
      Uri.parse('$voipgridUrl/api/v2/user/details'),
      headers: {..._jsonHeaders, 'Authorization': 'Bearer $token'},
    ),
  );

  if (!response.isSuccess) {
    throw Exception(
      'Fetching the user details failed: '
      '${response.statusCode} ${response.body}',
    );
  }

  print('   ✓ The token works\n');
}

Future<void> _notifySlackFailure(Object error, StackTrace stackTrace) async {
  final webhookUrl = _slackWebhookUrl;
  if (webhookUrl == null || webhookUrl.isEmpty) {
    stderr.writeln(
      '⚠️  Slack webhook URL not configured. Skipping notification.',
    );
    return;
  }

  try {
    final message = {
      'text': '❌ Vialer Test Environment Validation Failed',
      'blocks': [
        {
          'type': 'header',
          'text': {
            'type': 'plain_text',
            'text': '❌ Vialer Test Environment Validation Failed',
            'emoji': true,
          },
        },
        {
          'type': 'section',
          'text': {'type': 'mrkdwn', 'text': '*Error:*\n```$error```'},
        },
        {
          'type': 'section',
          'text': {
            'type': 'mrkdwn',
            'text':
                '*Stack Trace:*\n```${stackTrace.toString().split('\n').take(10).join('\n')}```',
          },
        },
        {
          'type': 'context',
          'elements': [
            {
              'type': 'mrkdwn',
              'text': 'Brand: $_brand | Credentials: $_username',
            },
          ],
        },
      ],
    };

    final response = await _send(
      'Slack notification',
      () => http.post(
        Uri.parse(webhookUrl),
        headers: _jsonHeaders,
        body: jsonEncode(message),
      ),
    );

    if (response.statusCode != 200) {
      stderr.writeln(
        '⚠️  Failed to send Slack notification: ${response.statusCode}',
      );
    }
  } catch (e) {
    stderr.writeln('⚠️  Error sending Slack notification: $e');
  }
}

extension on http.Response {
  bool get isSuccess => [200, 201, 204].contains(statusCode);
}

extension on String {
  String get masked {
    if (length <= 10) return '*' * length;
    final first5 = substring(0, 5);
    final last5 = substring(length - 5);
    return '$first5${"*" * (length - 10)}$last5';
  }
}
