import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// Remote control for the local [baresip](https://github.com/baresip/baresip)
/// SIP client, which acts as the remote party in calling tests so the app can
/// receive a real incoming call.
///
/// baresip is configured and started by `./utils/bin/run-integration-tests`,
/// which also makes [_host]:[_port] on the device reach the baresip running on
/// the host machine: through `adb reverse` on a local device, through the
/// egress tunnel on emulator.wtf.
///
/// Commands go over baresip's `ctrl_tcp` module, which speaks
/// [netstrings](https://cr.yp.to/proto/netstrings.txt) wrapping a JSON payload:
/// `<byte length of the json>:<json>,`.
class BaresipClient {
  BaresipClient._(this._socket, this._subscription, this._received);

  static const _host = String.fromEnvironment(
    'INTEGRATION_TEST_BARESIP_HOST',
    defaultValue: '127.0.0.1',
  );
  static const _port = 4444;
  static const _connectTimeout = Duration(seconds: 5);

  final Socket _socket;
  final StreamSubscription<Uint8List> _subscription;
  final StringBuffer _received;

  /// Only used to give every command a distinguishable token, which baresip
  /// echoes back in its response so the log can be correlated.
  int _commandCount = 0;

  static Future<BaresipClient> connect() async {
    // ignore: close_sinks
    final Socket socket;
    try {
      socket = await Socket.connect(_host, _port, timeout: _connectTimeout);
    } on SocketException catch (e, stackTrace) {
      Error.throwWithStackTrace(
        TestFailure(
          'Could not reach baresip on $_host:$_port ($e). It is started by '
          './utils/bin/run-integration-tests, so check ~/.baresip/baresip.log '
          'to see whether it came up and registered. A local Android device '
          'reaches the host through `adb reverse tcp:$_port tcp:$_port`, '
          'emulator.wtf through its egress tunnel; the same script sets up '
          'both.',
        ),
        stackTrace,
      );
    }

    final received = StringBuffer();

    // ignore: cancel_subscriptions
    final subscription = socket.listen(
      (data) {
        final text = utf8.decode(data, allowMalformed: true);
        received.write(text);
        debugPrint('[baresip] $text');
      },
      onError: (Object e) => debugPrint('[baresip] socket error: $e'),
    );

    return BaresipClient._(socket, subscription, received);
  }

  /// Whether baresip has reported that a call ended, which it broadcasts as a
  /// `CALL_CLOSED` event to every connected ctrl_tcp client.
  bool get hasSeenCallClosed => _events.any(
    (event) => event['type'] == 'CALL_CLOSED',
  );

  /// The DTMF digits baresip received from the app, in order.
  String get receivedDtmf => _events
      .where((event) => event['type'] == 'CALL_DTMF_START')
      .map((event) => event['param'])
      .join();

  /// Every message baresip sent so far, decoded from its netstrings.
  Iterable<Map<String, dynamic>> get _events sync* {
    final buffer = _received.toString();
    var offset = 0;
    while (true) {
      final separator = buffer.indexOf(':', offset);
      if (separator == -1) return;

      final length = int.tryParse(buffer.substring(offset, separator));
      final end = separator + 1 + (length ?? 0);
      if (length == null || end > buffer.length) return;

      final payload = jsonDecode(buffer.substring(separator + 1, end));
      if (payload is Map<String, dynamic>) yield payload;

      // Skip the trailing comma that closes every netstring.
      offset = end + 1;
    }
  }

  Future<void> dial(String number) => _send('dial', number);

  Future<void> hangup() => _send('hangup');

  /// Hangs up every call baresip has, such as after a transfer left it with
  /// a call to someone other than the app.
  Future<void> hangupAll() => _send('hangupall');

  Future<void> close() async {
    await _subscription.cancel();
    await _socket.flush();
    await _socket.close();
    _socket.destroy();
  }

  Future<void> _send(String command, [String params = '']) async {
    final payload = jsonEncode({
      'command': command,
      'params': params,
      'token': 'integration-test-${_commandCount++}',
    });

    debugPrint('[baresip] trying to send $payload');
    _socket.write('${utf8.encode(payload).length}:$payload,');
    await _socket.flush();
  }
}
