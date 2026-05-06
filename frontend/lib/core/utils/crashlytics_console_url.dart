import '../models/crash.dart';

/// Builds a Firebase Console Crashlytics issue URL for this crash.
///
/// Shape:
/// `https://console.firebase.google.com/u/0/project/{project}/crashlytics/app/{android:pkg|ios:bundle}/issues/{crashId}`
Uri? crashlyticsIssueUri(Crash crash, Map<String, dynamic> crashlytics) {
  final project = (crashlytics['firebase_console_project_id'] ?? crashlytics['project_id'])
      ?.toString()
      .trim();
  final crashId = crash.crashId.trim();
  if (project == null || project.isEmpty || crashId.isEmpty) return null;

  var appSeg = crash.crashlyticsConsoleAppId?.trim();
  appSeg ??= _composeAppSegment(
    crash.platform,
    crash.appIdentifier,
    crashlytics['android_package_default']?.toString(),
    crashlytics['ios_bundle_id_default']?.toString(),
  );
  if (appSeg == null || appSeg.isEmpty) return null;

  return Uri(
    scheme: 'https',
    host: 'console.firebase.google.com',
    pathSegments: ['u', '0', 'project', project, 'crashlytics', 'app', appSeg, 'issues', crashId],
  );
}

String? _composeAppSegment(
  String? platform,
  String? appIdentifier,
  String? androidPackageDefault,
  String? iosBundleDefault,
) {
  var bundle = (appIdentifier ?? '').trim();
  if (bundle.isEmpty) {
    final ad = (androidPackageDefault ?? '').trim();
    final id = (iosBundleDefault ?? '').trim();
    final plat = (platform ?? '').toLowerCase();
    final hintIos = plat.contains('ios') || plat == 'apple' || plat.contains('ipados');
    if (ad.isNotEmpty && id.isNotEmpty) {
      bundle = hintIos ? id : ad;
    } else if (ad.isNotEmpty) {
      bundle = ad;
    } else if (id.isNotEmpty) {
      bundle = id;
    } else {
      return null;
    }
  }

  final plat = (platform ?? '').toLowerCase();
  final isIos = plat.contains('ios') || plat == 'apple' || plat.contains('ipados');
  return '${isIos ? 'ios' : 'android'}:$bundle';
}
