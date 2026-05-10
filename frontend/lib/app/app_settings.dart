import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

@immutable
class AppSettings {
  final String apiBaseUrl;
  final ThemeMode themeMode;

  const AppSettings({required this.apiBaseUrl, required this.themeMode});

  AppSettings copyWith({String? apiBaseUrl, ThemeMode? themeMode}) =>
      AppSettings(
        apiBaseUrl: apiBaseUrl ?? this.apiBaseUrl,
        themeMode: themeMode ?? this.themeMode,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppSettings &&
          apiBaseUrl == other.apiBaseUrl &&
          themeMode == other.themeMode;

  @override
  int get hashCode => Object.hash(apiBaseUrl, themeMode);
}

/// Loads persisted settings **before** emitting [AsyncData], so dependents
/// like [apiClientProvider] are not built then torn down when prefs finish
/// loading (which used to dispose the first [ApiClient] mid-request).
class AppSettingsNotifier extends AsyncNotifier<AppSettings> {
  static const _kBaseUrl = 'app.api_base_url';
  static const _kThemeMode = 'app.theme_mode';

  static String defaultBaseUrl() {
    const fromDefine = String.fromEnvironment('API_BASE_URL', defaultValue: '');
    if (fromDefine.isNotEmpty) return fromDefine;
    if (kIsWeb) {
      // When served by the backend (packaged app), default to same origin so
      // dynamic ports work without manual configuration.
      final origin = Uri.base.origin.trim();
      if (origin.isNotEmpty) return origin;
    }
    return 'http://localhost:8000';
  }

  ThemeMode _parseMode(String? raw) {
    switch (raw) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      case 'system':
        return ThemeMode.system;
      default:
        return ThemeMode.dark;
    }
  }

  @override
  Future<AppSettings> build() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_kBaseUrl);
      final url = (raw == null || raw.trim().isEmpty)
          ? defaultBaseUrl()
          : raw.trim();
      final mode = _parseMode(p.getString(_kThemeMode));
      return AppSettings(apiBaseUrl: url, themeMode: mode);
    } catch (e) {
      if (kDebugMode) debugPrint('AppSettings load error: $e');
      return AppSettings(
        apiBaseUrl: defaultBaseUrl(),
        themeMode: ThemeMode.dark,
      );
    }
  }

  Future<void> setBaseUrl(String url) async {
    final trimmed = url.trim();
    final normalized = trimmed.isEmpty ? defaultBaseUrl() : trimmed;
    final prev = state.valueOrNull;
    if (prev == null) return;
    final next = prev.copyWith(apiBaseUrl: normalized);
    if (next == prev) {
      final p = await SharedPreferences.getInstance();
      await p.setString(_kBaseUrl, normalized);
      return;
    }
    state = AsyncData(next);
    final p = await SharedPreferences.getInstance();
    await p.setString(_kBaseUrl, normalized);
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    final prev = state.valueOrNull;
    if (prev == null) return;
    final next = prev.copyWith(themeMode: mode);
    if (next == prev) return;
    state = AsyncData(next);
    final p = await SharedPreferences.getInstance();
    await p.setString(_kThemeMode, mode.name);
  }
}

final appSettingsProvider =
    AsyncNotifierProvider<AppSettingsNotifier, AppSettings>(
  AppSettingsNotifier.new,
);
