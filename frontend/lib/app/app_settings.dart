import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppSettings {
  final String apiBaseUrl;
  final ThemeMode themeMode;
  const AppSettings({required this.apiBaseUrl, required this.themeMode});

  AppSettings copyWith({String? apiBaseUrl, ThemeMode? themeMode}) =>
      AppSettings(
        apiBaseUrl: apiBaseUrl ?? this.apiBaseUrl,
        themeMode: themeMode ?? this.themeMode,
      );
}

class AppSettingsNotifier extends Notifier<AppSettings> {
  static const _kBaseUrl = 'app.api_base_url';
  static const _kThemeMode = 'app.theme_mode';

  String get _defaultBaseUrl {
    const fromDefine = String.fromEnvironment('API_BASE_URL', defaultValue: '');
    if (fromDefine.isNotEmpty) return fromDefine;
    return 'http://localhost:8000';
  }

  @override
  AppSettings build() {
    Future.microtask(_load);
    return AppSettings(apiBaseUrl: _defaultBaseUrl, themeMode: ThemeMode.dark);
  }

  Future<void> _load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final url = p.getString(_kBaseUrl) ?? _defaultBaseUrl;
      final mode = _parseMode(p.getString(_kThemeMode));
      state = AppSettings(apiBaseUrl: url, themeMode: mode);
    } catch (e) {
      if (kDebugMode) debugPrint('AppSettings load error: $e');
    }
  }

  Future<void> setBaseUrl(String url) async {
    state = state.copyWith(apiBaseUrl: url);
    final p = await SharedPreferences.getInstance();
    await p.setString(_kBaseUrl, url);
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    state = state.copyWith(themeMode: mode);
    final p = await SharedPreferences.getInstance();
    await p.setString(_kThemeMode, mode.name);
  }

  ThemeMode _parseMode(String? raw) {
    switch (raw) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      case 'system':
      default:
        return ThemeMode.dark;
    }
  }
}

final appSettingsProvider =
    NotifierProvider<AppSettingsNotifier, AppSettings>(AppSettingsNotifier.new);
