// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../../ci_utils.dart';

const _codemagicBaseUrl = 'https://api.codemagic.io/builds';

/// The frequency at which api calls will be made when checking the build
/// status.
const _apiQueryInterval = Duration(seconds: 10);

const _artefactLinkLifetime = Duration(days: 7);

const _maxStepLogLines = 2000;

/// Starts a build on Codemagic and will then block until the build has
/// finished.
///
/// This is designed to be run in the Gitlab CI environment but for testing
/// purposes you can run it locally:
///
/// e.g.
///
/// `dart utils/ci/gitlab/build_via_codemagic.dart 5e78b819064d840016d04c7a main main {CODEMAGIC API KEY} 123`
Future<void> main(List<String> args) async {
  final appId = args.getOrEnvVar(0, 'CODEMAGIC_APP_ID');
  final codemagicApiToken = args.getOrEnvVar(3, 'CODEMAGIC_API_TOKEN');
  final mergeRequestBranch = args.getOrEnvVar(
    2,
    'CI_MERGE_REQUEST_SOURCE_BRANCH_NAME',
  );
  final branch = mergeRequestBranch.isNotEmpty
      ? mergeRequestBranch
      : Platform.environment['CI_COMMIT_REF_NAME'] ?? '';
  final mergeRequestIid = args.getOrEnvVar(4, 'CI_MERGE_REQUEST_IID');
  final mergeRequestTitle =
      Platform.environment['CI_MERGE_REQUEST_TITLE'] ?? '';
  final gitlabUser = Platform.environment['GITLAB_USER_LOGIN'] ?? '';
  final workflowId = args.getOrEnvVar(1, 'CODEMAGIC_WORKFLOW');

  final buildId = await _startCodemagicBuild(
    apiToken: codemagicApiToken,
    appId: appId,
    workflowId: workflowId,
    branch: branch,
    gitlabMergeRequestId: mergeRequestIid,
    gitlabMergeRequestApproved: args.getOrEnvVar(
      5,
      'CI_MERGE_REQUEST_APPROVED',
    ),
    labels: [
      if (mergeRequestIid.isNotEmpty) '!$mergeRequestIid: $mergeRequestTitle',
      if (gitlabUser.isNotEmpty) '@$gitlabUser',
    ],
    emulatorWtfArgs: Platform.environment['EMULATOR_WTF_ARGS'] ?? '',
  );
  File(codemagicBuildIdFile).writeAsStringSync(buildId);

  final buildLink = (
    label: 'Codemagic build',
    url: codemagicBuildUrl(appId, buildId),
  );
  _printHeader(
    build: await _fetchCodemagicBuild(
      apiToken: codemagicApiToken,
      buildId: buildId,
    ),
    buildUrl: buildLink.url,
    mergeRequest: mergeRequestIid.isNotEmpty
        ? '!$mergeRequestIid $mergeRequestTitle'
        : null,
    gitlabUser: gitlabUser,
  );
  _writeAnnotations(buildLink: buildLink);

  final build = await _followBuild(
    apiToken: codemagicApiToken,
    buildId: buildId,
    buildUrl: buildLink.url,
  );

  _writeAnnotations(
    buildLink: buildLink,
    artefactLinks: await _publicArtefactLinks(
      apiToken: codemagicApiToken,
      artefacts: build.artefacts,
    ),
  );

  final passed = build.status == _CodemagicBuildStatus.complete;

  printBox(
    [
      if (passed)
        '✓ Codemagic build finished'
      else
        '✗ Codemagic build ${build.rawStatus} on: ${build.currentStage}',
      buildLink.url,
    ],
    topLeft: '╠',
    titleStyle: '$ansiBold${passed ? ansiGreen : ansiRed}',
  );

  exit(passed ? 0 : 1);
}

void _printHeader({
  required _CodemagicBuild build,
  required String buildUrl,
  required String? mergeRequest,
  required String gitlabUser,
}) {
  final commit = build.commit;
  final details = {
    'Workflow': build.workflow,
    'Branch': build.branch,
    if (commit != null) ...{
      'Commit': '${commit.shortHash} ${commit.subject}',
      'Author': commit.authorName,
    },
    'Merge request': ?mergeRequest,
    if (gitlabUser.isNotEmpty) 'Triggered by': '@$gitlabUser',
    'Machine': build.instanceType,
  }..removeWhere((_, value) => value == null || value.isEmpty);
  final keyWidth = details.keys.map((key) => key.length).reduce(max) + 2;

  print('');
  printBox(
    [
      '▶ STARTING CODEMAGIC BUILD',
      '',
      for (final MapEntry(:key, :value) in details.entries)
        '${'$key:'.padRight(keyWidth)}$value',
      buildUrl,
    ],
    bottomLeft: '╠',
    titleStyle: '$ansiBold$ansiYellow',
  );
}

/// Polls Codemagic until the build is finished, cancelled or failed, printing
/// only when the build moves on and each step's log once that step completes.
Future<_CodemagicBuild> _followBuild({
  required String apiToken,
  required String buildId,
  required String buildUrl,
}) async {
  final printedStepIds = <String>{};
  String? lastProgress;

  while (true) {
    final build = await _fetchCodemagicBuild(
      apiToken: apiToken,
      buildId: buildId,
    );
    final isPending = build.status == _CodemagicBuildStatus.pending;

    // Log URLs can lag behind a step's finish, so wait for them unless the
    // build is over.
    final completedSteps = build.steps.where(
      (step) => step.isFinished && (step.logUrls.isNotEmpty || !isPending),
    );

    for (final step in completedSteps) {
      if (printedStepIds.add(step.id)) {
        await _printStepLog(apiToken: apiToken, step: step, buildUrl: buildUrl);
      }
    }

    if (!isPending) return build;

    final runningStep = build.runningStep;
    final progress = runningStep != null
        ? '$ansiDim▷ ${runningStep.name}$ansiReset'
        : '$ansiYellow◆ Codemagic build is ${build.rawStatus}$ansiReset';

    if (progress != lastProgress) {
      _printInGutter(progress);
      lastProgress = progress;
    }

    await Future<void>.delayed(_apiQueryInterval);
  }
}

/// Prints the step's log in a GitLab collapsible section, which is expanded
/// when the step didn't pass.
Future<void> _printStepLog({
  required String apiToken,
  required _CodemagicStep step,
  required String buildUrl,
}) async {
  final section = 'codemagic_step_${step.id}';
  final passed = step.status == 'success';
  final header = passed ? '$ansiGreen✓ ${step.name}' : '$ansiRed✗ ${step.name}';

  print(
    '$ansiClearLine'
    'section_start:${step.startedAt.unixSeconds}:$section'
    '[collapsed=$passed]\r$ansiClearLine$_gutter $header$ansiReset',
  );

  if (step.logUrls.isEmpty) {
    _printInGutter('No log available for this step.');
  }

  final lines = <String>[];

  for (final logUrl in step.logUrls) {
    try {
      final log = await _fetchStepLog(apiToken: apiToken, logUrl: logUrl);
      lines.addAll(log.trimRight().split('\n'));
    } on Exception catch (e) {
      lines.add('Unable to fetch the log for this step: $e');
    }
  }

  final hiddenLines = lines.length - _maxStepLogLines;

  if (hiddenLines > 0) {
    lines.removeRange(0, hiddenLines);
    _printInGutter(
      '$ansiYellow… $hiddenLines earlier lines hidden, full log: '
      '$buildUrl?open-step=build-step-${step.index}$ansiReset',
    );
  }

  lines.forEach(_printInGutter);

  print(
    '$ansiClearLine'
    'section_end:${step.finishedAt.unixSeconds}:$section\r$ansiClearLine',
  );
}

void _printInGutter(String line) => print('$_gutter $line');

const _gutter = '$ansiCyan║$ansiReset';

Future<String> _fetchStepLog({
  required String apiToken,
  required String logUrl,
}) async {
  final request = await HttpClient().getUrl(Uri.parse(logUrl));
  request.headers.set('x-auth-token', apiToken);
  final response = await request.close();
  final body = await readResponse(response);

  if (response.statusCode != HttpStatus.ok) {
    throw HttpException('HTTP ${response.statusCode}', uri: Uri.parse(logUrl));
  }

  return body.htmlToPlainText();
}

typedef _Link = ({String label, String url});

/// Shown as links in the GitLab job page sidebar.
void _writeAnnotations({
  required _Link buildLink,
  List<_Link> artefactLinks = const [],
}) => File('annotations.json').writeAsStringSync(
  jsonEncode({
    'codemagic': [buildLink.toExternalLink()],
    if (artefactLinks.isNotEmpty)
      'artefacts': [for (final link in artefactLinks) link.toExternalLink()],
  }),
);

/// Codemagic artefacts need a login to download, so these links let anyone
/// with access to the GitLab job download them until they expire.
Future<List<_Link>> _publicArtefactLinks({
  required String apiToken,
  required List<_CodemagicArtefact> artefacts,
}) async {
  final expiresAt = DateTime.now().add(_artefactLinkLifetime);
  final links = <_Link>[];

  for (final artefact in artefacts) {
    try {
      links.add((
        label: artefact.name,
        url: await _createPublicUrl(
          apiToken: apiToken,
          artefactUrl: artefact.url,
          expiresAt: expiresAt,
        ),
      ));
    } on Exception catch (e) {
      _printInGutter(
        'Unable to create a download link for ${artefact.name}: $e',
      );
    }
  }

  return links;
}

Future<String> _createPublicUrl({
  required String apiToken,
  required String artefactUrl,
  required DateTime expiresAt,
}) async {
  final uri = Uri.parse('$artefactUrl/public-url');
  final request = await HttpClient().postUrl(uri);
  request.headers.set('x-auth-token', apiToken);
  request.headers.set('Content-Type', 'application/json');
  request.write(jsonEncode({'expiresAt': expiresAt.unixSeconds}));
  final response = await request.close();
  final body = await readResponse(response);

  if (response.statusCode ~/ 100 != 2) {
    throw HttpException('HTTP ${response.statusCode}', uri: uri);
  }

  return (jsonDecode(body) as Map<String, dynamic>)['url'] as String;
}

Future<String> _startCodemagicBuild({
  required String apiToken,
  required String appId,
  required String workflowId,
  required String branch,
  required String gitlabMergeRequestId,
  required String gitlabMergeRequestApproved,
  required List<String> labels,
  required String emulatorWtfArgs,
}) async => HttpClient()
    .postUrl(Uri.parse(_codemagicBaseUrl))
    .then((request) {
      request.headers.set('x-auth-token', apiToken);
      request.headers.set('Content-Type', 'application/json');
      request.write(
        json.encode({
          'appId': appId,
          'workflowId': workflowId,
          'branch': branch,
          'labels': labels,
          'environment': {
            'variables': {
              'GITLAB_MERGE_REQUEST_IID': gitlabMergeRequestId,
              'GITLAB_MERGE_REQUEST_APPROVED': gitlabMergeRequestApproved,
              if (emulatorWtfArgs.isNotEmpty)
                'EMULATOR_WTF_ARGS': emulatorWtfArgs,
            },
          },
        }),
      );

      return request.close();
    })
    .then(readResponse)
    .then(jsonDecode)
    .then((value) => value as Map<String, dynamic>)
    .then((response) => response['buildId'] as String);

Future<_CodemagicBuild> _fetchCodemagicBuild({
  required String apiToken,
  required String buildId,
  bool retry = true,
}) async {
  final build = await HttpClient()
      .getUrl(Uri.parse('$_codemagicBaseUrl/$buildId'))
      .then((request) {
        request.headers.set('x-auth-token', apiToken);
        return request.close();
      })
      .then(readResponse)
      .then(jsonDecode)
      .then((value) => value as Map<String, dynamic>)
      .then((response) => response['build'] as Map<String, dynamic>?);

  final status = build?['status'] as String?;

  if (status == null || build == null) {
    if (!retry) {
      throw Exception('Unable to fetch codemagic build: [$buildId].');
    }

    // If we weren't able to fetch the build immediately, we will wait briefly
    // and then try again.
    sleep(_apiQueryInterval);
    return _fetchCodemagicBuild(
      apiToken: apiToken,
      buildId: buildId,
      retry: false,
    );
  }

  return _CodemagicBuild.fromJson(build);
}

class _CodemagicBuild {
  _CodemagicBuild.fromJson(Map<String, dynamic> json)
    : rawStatus = json['status'] as String,
      workflow = (json['fileWorkflowId'] ?? json['workflowId']) as String?,
      branch = json['branch'] as String?,
      instanceType = json['instanceType'] as String?,
      commit = switch (json['commit']) {
        final Map<String, dynamic> commit => _CodemagicCommit.fromJson(commit),
        _ => null,
      },
      steps = (json['buildActions'] as List<Object?>)
          .cast<Map<String, dynamic>>()
          .indexed
          .map((entry) => _CodemagicStep.fromJson(entry.$2, index: entry.$1))
          .toList(),
      artefacts = (json['artefacts'] as List<Object?>? ?? [])
          .cast<Map<String, dynamic>>()
          .map(_CodemagicArtefact.fromJson)
          .toList();

  final String rawStatus;
  final String? workflow;
  final String? branch;
  final String? instanceType;
  final _CodemagicCommit? commit;
  final List<_CodemagicStep> steps;
  final List<_CodemagicArtefact> artefacts;

  _CodemagicBuildStatus get status => rawStatus.toCodemagicBuildStatus();

  _CodemagicStep? get runningStep =>
      steps.where((step) => step.isRunning).lastOrNull;

  _CodemagicStep? get _failedStep =>
      steps.where((step) => step.status == 'failed').firstOrNull;

  _CodemagicStep? get _lastStartedStep =>
      steps.where((step) => step.startedAt != null).lastOrNull;

  String get currentStage =>
      (_failedStep ?? _lastStartedStep)?.name ?? 'unknown';
}

/// A Codemagic build action. Codemagic's own steps carry their log URL
/// directly, script steps on their subactions.
class _CodemagicStep {
  _CodemagicStep.fromJson(Map<String, dynamic> json, {required this.index})
    : id = json['_id'] as String,
      name = json['name'] as String,
      status = json['status'] as String?,
      startedAt = DateTime.tryParse(json['startedAt'] as String? ?? ''),
      finishedAt = DateTime.tryParse(json['finishedAt'] as String? ?? ''),
      logUrls = [
        json['logUrl'] as String?,
        for (final subaction in json['subactions'] as List<Object?>? ?? [])
          (subaction as Map<String, dynamic>)['logUrl'] as String?,
      ].nonNulls.toList();

  final String id;
  final int index;
  final String name;
  final String? status;
  final DateTime? startedAt;
  final DateTime? finishedAt;
  final List<String> logUrls;

  bool get isRunning => startedAt != null && finishedAt == null;

  bool get isFinished => startedAt != null && finishedAt != null;
}

class _CodemagicCommit {
  _CodemagicCommit.fromJson(Map<String, dynamic> json)
    : hash = json['hash'] as String? ?? '',
      message = json['commitMessage'] as String? ?? '',
      authorName = json['authorName'] as String?;

  final String hash;
  final String message;
  final String? authorName;

  String get shortHash => hash.length > 8 ? hash.substring(0, 8) : hash;

  String get subject {
    final firstLine = message.split('\n').first.trim();
    return firstLine.length > _maxSubjectLength
        ? '${firstLine.substring(0, _maxSubjectLength)}…'
        : firstLine;
  }

  static const _maxSubjectLength = 60;
}

class _CodemagicArtefact {
  _CodemagicArtefact.fromJson(Map<String, dynamic> json)
    : name = json['name'] as String,
      url = json['url'] as String;

  final String name;
  final String url;
}

enum _CodemagicBuildStatus { complete, failed, pending }

extension on String {
  _CodemagicBuildStatus toCodemagicBuildStatus() {
    switch (this) {
      case 'finished':
        return _CodemagicBuildStatus.complete;
      case 'failed':
      case 'canceled':
      case 'timeout':
      case 'skipped':
        return _CodemagicBuildStatus.failed;
      default:
        return _CodemagicBuildStatus.pending;
    }
  }
}

/// Codemagic serves step logs as HTML, with colours as `<span>` tags.
extension on String {
  String htmlToPlainText() => replaceAll(RegExp('</?span[^>]*>'), '')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&#x27;', "'")
      .replaceAll('&amp;', '&');
}

extension on DateTime? {
  int get unixSeconds =>
      (this ?? DateTime.now()).millisecondsSinceEpoch ~/ 1000;
}

extension on _Link {
  Map<String, Object> toExternalLink() => {
    'external_link': {'label': label, 'url': url},
  };
}

extension on List<String> {
  String getOrEnvVar(int index, String envVar) {
    if (length >= index + 1) {
      return elementAt(index);
    } else {
      final value = Platform.environment[envVar];
      return value ?? '';
    }
  }
}
