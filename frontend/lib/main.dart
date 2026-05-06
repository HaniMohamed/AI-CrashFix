import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';

import 'app/app.dart';

void main() {
  // Ensure `/#/path` deep links work on Flutter web.
  setUrlStrategy(const HashUrlStrategy());
  runApp(const ProviderScope(child: AiCrashFixApp()));
}
