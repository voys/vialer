import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:vialer/data/models/call_records/call_record.dart';
import 'package:vialer/data/repositories/call_records/personal/recent_call_repository.dart';
import 'package:vialer/dependency_locator.dart';
import 'package:vialer/domain/usecases/user/get_logged_in_user.dart';
import 'package:vialer/domain/usecases/voipgrid/get_voipgrid_base_url.dart';

import '../utils/test_extensions.dart';
import '../utils/test_log.dart';

const _minimumAudioDuration = Duration(seconds: 4);
const _pollInterval = Duration(seconds: 5);
const _pollAttempts = 12;

Future<void> verifyCallHadAudio(
  IntegrationTestContext context, {
  required Direction direction,
  required DateTime placedAfter,
  String? thirdPartyNumber,
}) async {
  final description =
      'The ${direction.name} call carried audio, according to its recording';

  if (context.config.skipTestingCallMediaEstablished) {
    TestLog.skip(
      description,
      because:
          'media does not establish on this runner, so the call cannot have '
          'carried the audio this would assert on',
    );
    return;
  }

  await TestLog.test(
    description,
    () => _verifyCallHadAudio(
      context.tester,
      direction: direction,
      placedAfter: placedAfter,
      thirdPartyNumber: thirdPartyNumber,
    ),
  );
}

Future<void> _verifyCallHadAudio(
  WidgetTester tester, {
  required Direction direction,
  required DateTime placedAfter,
  required String? thirdPartyNumber,
}) async {
  TestLog.detail('Placed after', placedAfter);
  TestLog.detail('Other party', thirdPartyNumber ?? 'any');
  TestLog.detail(
    'Minimum audio in the recording',
    '${_minimumAudioDuration.inSeconds}s',
  );

  TestLog.step('⏳', 'Waiting for the call to show in the call history');

  final callId = await _pollUntilAvailable(
    tester,
    () => _idOfTheCallWeJustMade(
      direction: direction,
      placedAfter: placedAfter,
      thirdPartyNumber: thirdPartyNumber,
    ),
    reason: 'The call that was just made should appear in the call history',
  );

  TestLog.detail('Call', callId);
  TestLog.step('⏳', 'Waiting for the recording to be available');

  final recording = await _pollUntilAvailable(
    tester,
    () => _downloadRecording(callId),
    reason: 'A recording should be available for call $callId',
  );

  final audio = recording.bodyBytes;

  expect(
    audio.looksLikeWav,
    isTrue,
    reason:
        'The download for call $callId is not a WAV file, so whatever the API '
        'returned is not a recording',
  );

  final wav = audio.asWavFile;

  TestLog.detail(
    'Recording',
    '${recording.audioDescription}, ${wav.sampleRate}Hz '
        '${wav.bitsPerSample}-bit, ${wav.channels} channel(s), format '
        '${wav.audioFormat}, ${wav.duration.inMilliseconds}ms of audio',
  );

  expect(
    wav.duration,
    greaterThanOrEqualTo(_minimumAudioDuration),
    reason:
        'The recording of call $callId holds only ${wav.duration.inMilliseconds}ms '
        'of audio, so the call did not carry the audio it should have',
  );
}

typedef _WavFile = ({
  int audioFormat,
  int channels,
  int sampleRate,
  int bitsPerSample,
  Duration duration,
});

Future<String?> _idOfTheCallWeJustMade({
  required Direction direction,
  required DateTime placedAfter,
  required String? thirdPartyNumber,
}) async {
  final records = await dependencyLocator<RecentCallRepository>()
      .getRecentCalls(page: 1);

  return records
      .firstWhereOrNull(
        (record) => record.wasPlacedByThisTest(
          direction: direction,
          after: placedAfter,
          thirdPartyNumber: thirdPartyNumber,
        ),
      )
      ?.id;
}

/// The app itself has no use for recordings, so there is no service for them
/// and the API is called directly.
Future<http.Response?> _downloadRecording(String callId) async {
  final user = GetLoggedInUserUseCase()();
  final url = Uri.parse(GetVoipgridBaseUrlUseCase()()).resolve(
    'api/v2/clients/${user.client.uuid}/callrecordings/$callId/audio',
  );

  final response = await http.get(
    url,
    headers: {'Authorization': 'Bearer ${user.token}'},
  );

  return response.statusCode == 200 ? response : null;
}

Future<T> _pollUntilAvailable<T extends Object>(
  WidgetTester tester,
  Future<T?> Function() attempt, {
  required String reason,
}) async {
  for (var i = 0; i < _pollAttempts; i++) {
    final result = await attempt();
    if (result != null) return result;

    await tester.pumpFor(_pollInterval);
  }

  fail('$reason, but it did not within ${_pollInterval * _pollAttempts}');
}

extension on CallRecord {
  bool wasPlacedByThisTest({
    required Direction direction,
    required DateTime after,
    required String? thirdPartyNumber,
  }) =>
      this.direction == direction &&
      date.isAfter(after) &&
      (thirdPartyNumber == null ||
          this.thirdPartyNumber.digitsOnly == thirdPartyNumber.digitsOnly);
}

extension on http.Response {
  String get audioDescription =>
      '${bodyBytes.length} bytes, '
      'type ${headers['content-type']}, '
      'file ${headers['content-disposition']}';
}

extension on Uint8List {
  bool get looksLikeWav =>
      length >= 12 &&
      String.fromCharCodes(sublist(0, 4)) == 'RIFF' &&
      String.fromCharCodes(sublist(8, 12)) == 'WAVE';

  _WavFile get asWavFile {
    final bytes = buffer.asByteData(offsetInBytes, lengthInBytes);

    var audioFormat = 0;
    var channels = 0;
    var sampleRate = 0;
    var byteRate = 0;
    var bitsPerSample = 0;
    var dataSize = 0;

    var offset = 12;
    while (offset + 8 <= lengthInBytes) {
      final id = String.fromCharCodes(sublist(offset, offset + 4));
      final size = bytes.getUint32(offset + 4, Endian.little);
      final payload = offset + 8;

      if (id == 'fmt ' && payload + 16 <= lengthInBytes) {
        audioFormat = bytes.getUint16(payload, Endian.little);
        channels = bytes.getUint16(payload + 2, Endian.little);
        sampleRate = bytes.getUint32(payload + 4, Endian.little);
        byteRate = bytes.getUint32(payload + 8, Endian.little);
        bitsPerSample = bytes.getUint16(payload + 14, Endian.little);
      } else if (id == 'data') {
        final remaining = lengthInBytes - payload;
        dataSize = size == 0 || size > remaining ? remaining : size;
        break;
      }

      offset = payload + size + (size.isOdd ? 1 : 0);
    }

    return (
      audioFormat: audioFormat,
      channels: channels,
      sampleRate: sampleRate,
      bitsPerSample: bitsPerSample,
      duration: byteRate == 0
          ? Duration.zero
          : Duration(microseconds: (dataSize / byteRate * 1000000).round()),
    );
  }
}

extension on String {
  String get digitsOnly => replaceAll(RegExp(r'\D'), '');
}
