import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'app/router.dart';
import 'app/url_strategy_stub.dart'
    if (dart.library.html) 'app/url_strategy_web.dart';

void main() {
  configureUrlStrategy();
  final router = createAppRouter();
  runApp(ProviderScope(child: FixoraApp(router: router)));
}
