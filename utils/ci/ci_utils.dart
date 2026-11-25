// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';
import 'dart:math';

const codemagicBuildIdFile = 'codemagic_build_id';

const ansiClearLine = '\x1B[0K';
const ansiBold = '\x1B[1m';
const ansiDim = '\x1B[2m';
const ansiCyan = '\x1B[36m';
const ansiGreen = '\x1B[32m';
const ansiRed = '\x1B[31m';
const ansiYellow = '\x1B[33m';
const ansiReset = '\x1B[0m';

Future<String> readResponse(HttpClientResponse response) =>
    response.transform(utf8.decoder).join();

String codemagicBuildUrl(String appId, String buildId) =>
    'https://codemagic.io/app/$appId/build/$buildId';

void printBox(
  List<String> lines, {
  String color = ansiCyan,
  String topLeft = '╔',
  String bottomLeft = '╚',
  String titleStyle = ansiBold,
}) {
  final width = lines.map((line) => line.length).reduce(max);
  final border = '═' * (width + 4);
  final side = '$color║$ansiReset';

  print('$color$topLeft$border╗$ansiReset');
  for (final (index, line) in lines.indexed) {
    final style = index == 0 ? titleStyle : '';
    print('$side  $style${line.padRight(width)}$ansiReset  $side');
  }
  print('$color$bottomLeft$border╝$ansiReset');
}
