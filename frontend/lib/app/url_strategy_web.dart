import 'package:flutter_web_plugins/flutter_web_plugins.dart';

/// Web-only: enable `/#/path` deep links for Flutter web.
void configureUrlStrategy() {
  setUrlStrategy(const HashUrlStrategy());
}
