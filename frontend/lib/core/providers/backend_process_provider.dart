import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// When this app shipped as a desktop bundle, this provider handled booting an
/// embedded backend. The project is now **web-only**, so the backend is always
/// assumed to be external (configured via settings / `--dart-define`).
///
/// We keep the provider as an `AsyncValue` so existing UI and API wiring can
/// continue to:
/// - gate on `isLoading` / `hasError` (desktop-only behavior)
/// - optionally prefer an embedded backend base URL (`valueOrNull?.baseUrl`)
class BackendBoot {
  final String baseUrl;
  const BackendBoot({required this.baseUrl});
}

class BackendProcessNotifier extends AsyncNotifier<BackendBoot?> {
  @override
  Future<BackendBoot?> build() async {
    // Web-only: never start an embedded backend.
    //
    // Returning synchronously ensures callers don't get stuck behind a loading
    // screen (the previous desktop behavior).
    if (kIsWeb) return null;
    return null;
  }
}

final backendProcessProvider =
    AsyncNotifierProvider<BackendProcessNotifier, BackendBoot?>(
  BackendProcessNotifier.new,
);

