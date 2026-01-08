import 'package:freezed_annotation/freezed_annotation.dart';

part 'build_info.freezed.dart';

@freezed
abstract class BuildInfo with _$BuildInfo {
  const factory BuildInfo({
    required String version,
    required String packageName,
    required bool isProduction,
    String? buildNumber,
    String? mergeRequestNumber,
    String? branchName,
    String? tag,
  }) = _BuildInfo;
}
