import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists the session bearer token with Keychain on Apple platforms.
///
/// macOS dev builds often lack Data Protection Keychain entitlements; we use the
/// legacy keychain (`useDataProtectionKeyChain: false`) and fall back to
/// SharedPreferences if Keychain is still unavailable.
class SessionTokenStore {
  SessionTokenStore._();

  static const _tokenKey = 'fixora_session_token';
  static const _fallbackKey = 'fixora_session_token_fallback';

  static const FlutterSecureStorage _storage = FlutterSecureStorage(
    mOptions: MacOsOptions(
      useDataProtectionKeyChain: false,
      accessibility: KeychainAccessibility.unlocked,
    ),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.unlocked,
    ),
  );

  static Future<String?> read() async {
    try {
      final secure = await _storage.read(key: _tokenKey);
      if (secure != null && secure.isNotEmpty) {
        return secure;
      }
    } catch (_) {
      // Keychain unavailable — try fallback below.
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_fallbackKey);
    } catch (_) {
      return null;
    }
  }

  static Future<void> write(String token) async {
    try {
      await _storage.write(key: _tokenKey, value: token);
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_fallbackKey);
      } catch (_) {}
      return;
    } catch (_) {
      // Legacy keychain failed — persist for this install only.
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_fallbackKey, token);
    }
  }

  static Future<void> delete() async {
    try {
      await _storage.delete(key: _tokenKey);
    } catch (_) {}
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_fallbackKey);
    } catch (_) {}
  }
}
