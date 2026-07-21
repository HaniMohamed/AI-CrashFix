import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

class AppVersionInfo {
  final String appName;
  final String version;
  final String buildNumber;

  const AppVersionInfo({
    required this.appName,
    required this.version,
    required this.buildNumber,
  });

  /// e.g. `v0.1.0 (1)`
  String get shortLabel => 'v$version ($buildNumber)';

  /// e.g. `0.1.0 · build 1`
  String get detailLabel => '$version · build $buildNumber';
}

final appVersionProvider = FutureProvider<AppVersionInfo>((ref) async {
  final info = await PackageInfo.fromPlatform();
  return AppVersionInfo(
    appName: info.appName,
    version: info.version,
    buildNumber: info.buildNumber,
  );
});
