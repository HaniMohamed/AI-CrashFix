import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Web-only frontend: the backend is assumed to be external.
///
/// This provider is kept so existing consumers can remain unchanged; it
/// always resolves to `null`.
final backendProcessProvider = Provider<void>((ref) {
  if (!kIsWeb) {
    // Still web-only by policy; no embedded backend support.
  }
});

