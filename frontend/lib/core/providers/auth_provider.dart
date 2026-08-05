import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../app/app_settings.dart';
import '../api/api_client.dart';
import '../api/endpoints.dart';
import 'backend_process_provider.dart';

const _tokenStorageKey = 'fixora_session_token';

class AuthUser {
  final String id;
  final String username;
  final String tenantUserId;
  final String role;
  final String status;
  final bool mustChangePassword;

  const AuthUser({
    required this.id,
    required this.username,
    required this.tenantUserId,
    required this.role,
    required this.status,
    required this.mustChangePassword,
  });

  factory AuthUser.fromJson(Map<String, dynamic> json) {
    return AuthUser(
      id: '${json['id'] ?? ''}',
      username: '${json['username'] ?? ''}',
      tenantUserId: '${json['tenant_user_id'] ?? ''}',
      role: '${json['role'] ?? 'user'}',
      status: '${json['status'] ?? 'active'}',
      mustChangePassword: json['must_change_password'] == true,
    );
  }

  bool get isAdmin => role == 'admin';
  bool get isBlocked => status == 'blocked';
}

class AuthState {
  final bool initialized;
  final bool loading;
  final String? token;
  final AuthUser? user;
  final bool needsAdmin;
  final bool needsStoreSetup;
  final String? error;

  const AuthState({
    this.initialized = false,
    this.loading = false,
    this.token,
    this.user,
    this.needsAdmin = false,
    this.needsStoreSetup = false,
    this.error,
  });

  bool get isAuthenticated => token != null && user != null;

  AuthState copyWith({
    bool? initialized,
    bool? loading,
    String? token,
    AuthUser? user,
    bool? needsAdmin,
    bool? needsStoreSetup,
    String? error,
    bool clearToken = false,
    bool clearUser = false,
    bool clearError = false,
  }) {
    return AuthState(
      initialized: initialized ?? this.initialized,
      loading: loading ?? this.loading,
      token: clearToken ? null : (token ?? this.token),
      user: clearUser ? null : (user ?? this.user),
      needsAdmin: needsAdmin ?? this.needsAdmin,
      needsStoreSetup: needsStoreSetup ?? this.needsStoreSetup,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// API client without auth — used for login/bootstrap before a token exists.
final baseApiClientProvider = Provider<ApiClient>((ref) {
  final settings = ref.watch(appSettingsProvider).requireValue;
  final backend = ref.watch(backendProcessProvider).valueOrNull;
  final client = ApiClient(baseUrl: backend?.baseUrl ?? settings.apiBaseUrl);
  ref.onDispose(client.close);
  return client;
});

class AuthNotifier extends Notifier<AuthState> {
  static const _storage = FlutterSecureStorage();

  @override
  AuthState build() {
    Future.microtask(_initialize);
    return const AuthState(loading: true);
  }

  Future<void> _initialize() async {
    try {
      final token = await _storage.read(key: _tokenStorageKey);
      if (token != null && token.isNotEmpty) {
        state = state.copyWith(token: token, loading: true);
        await _refreshMe(token);
      } else {
        await _fetchBootstrapStatus();
        state = state.copyWith(initialized: true, loading: false);
      }
    } catch (e) {
      state = state.copyWith(
        initialized: true,
        loading: false,
        error: '$e',
      );
    }
  }

  Future<void> _fetchBootstrapStatus() async {
    final api = ref.read(baseApiClientProvider);
    final res = await api.getJson(Endpoints.authBootstrapStatus);
    final map = (res as Map).cast<String, dynamic>();
    state = state.copyWith(
      needsAdmin: map['needs_admin'] == true,
      needsStoreSetup: map['needs_store_setup'] == true,
    );
  }

  Future<void> refreshBootstrapStatus() async {
    await _fetchBootstrapStatus();
    state = state.copyWith(initialized: true);
  }

  Future<void> _refreshMe(String token) async {
    final settings = ref.read(appSettingsProvider).requireValue;
    final backend = ref.read(backendProcessProvider).valueOrNull;
    final client = ApiClient(
      baseUrl: backend?.baseUrl ?? settings.apiBaseUrl,
      authToken: token,
    );
    try {
      final res = await client.getJson(Endpoints.authMe);
      final userMap = (res as Map)['user'] as Map;
      state = state.copyWith(
        initialized: true,
        loading: false,
        token: token,
        user: AuthUser.fromJson(userMap.cast<String, dynamic>()),
        clearError: true,
      );
      await _fetchBootstrapStatus();
    } finally {
      client.close();
    }
  }

  Future<String?> bootstrapAdmin({
    required String username,
    String? tenantUserId,
  }) async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final api = ref.read(baseApiClientProvider);
      final body = <String, dynamic>{'username': username};
      if (tenantUserId != null && tenantUserId.trim().isNotEmpty) {
        body['tenant_user_id'] = tenantUserId.trim();
      }
      final res = await api.postJson(Endpoints.authBootstrapAdmin, body: body);
      final map = (res as Map).cast<String, dynamic>();
      state = state.copyWith(
        loading: false,
        needsAdmin: false,
        needsStoreSetup: false,
        initialized: true,
      );
      return map['temp_password']?.toString();
    } catch (e) {
      state = state.copyWith(loading: false, error: '$e');
      return null;
    }
  }

  Future<bool> login(String username, String password) async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final api = ref.read(baseApiClientProvider);
      final res = await api.postJson(
        Endpoints.authLogin,
        body: {'username': username, 'password': password},
      );
      final map = (res as Map).cast<String, dynamic>();
      final token = map['token']?.toString();
      if (token == null || token.isEmpty) {
        throw Exception('No session token returned');
      }
      await _storage.write(key: _tokenStorageKey, value: token);
      final userMap = (map['user'] as Map).cast<String, dynamic>();
      state = state.copyWith(
        loading: false,
        token: token,
        user: AuthUser.fromJson(userMap),
        needsAdmin: false,
        clearError: true,
      );
      return true;
    } catch (e) {
      state = state.copyWith(loading: false, error: '$e');
      return false;
    }
  }

  Future<bool> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final token = state.token;
    if (token == null) return false;
    state = state.copyWith(loading: true, clearError: true);
    try {
      final settings = ref.read(appSettingsProvider).requireValue;
      final backend = ref.read(backendProcessProvider).valueOrNull;
      final client = ApiClient(
        baseUrl: backend?.baseUrl ?? settings.apiBaseUrl,
        authToken: token,
      );
      final res = await client.postJson(
        Endpoints.authChangePassword,
        body: {
          'current_password': currentPassword,
          'new_password': newPassword,
        },
      );
      client.close();
      final userMap = (res as Map)['user'] as Map;
      state = state.copyWith(
        loading: false,
        user: AuthUser.fromJson(userMap.cast<String, dynamic>()),
        clearError: true,
      );
      return true;
    } catch (e) {
      state = state.copyWith(loading: false, error: '$e');
      return false;
    }
  }

  Future<void> logout() async {
    final token = state.token;
    if (token != null) {
      try {
        final settings = ref.read(appSettingsProvider).requireValue;
        final backend = ref.read(backendProcessProvider).valueOrNull;
        final client = ApiClient(
          baseUrl: backend?.baseUrl ?? settings.apiBaseUrl,
          authToken: token,
        );
        await client.postJson(Endpoints.authLogout);
        client.close();
      } catch (_) {}
    }
    await _storage.delete(key: _tokenStorageKey);
    state = const AuthState(initialized: true, loading: false);
    await _fetchBootstrapStatus();
    state = state.copyWith(initialized: true);
  }

  void handleUnauthorized() {
    _storage.delete(key: _tokenStorageKey);
    state = AuthState(
      initialized: true,
      loading: false,
      needsAdmin: state.needsAdmin,
    );
  }
}

final authProvider = NotifierProvider<AuthNotifier, AuthState>(AuthNotifier.new);
