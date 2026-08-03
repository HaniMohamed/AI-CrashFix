import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../app/brand.dart';

/// Starts and manages the packaged FastAPI backend for desktop builds.
///
/// Web: does nothing (assumes backend is external).
/// macOS: launches a bundled binary and polls /api/health until ready.
class BackendBoot {
  final String baseUrl;
  final int port;
  final String? backendPath;
  const BackendBoot({
    required this.baseUrl,
    required this.port,
    this.backendPath,
  });
}

const _backendChannel = MethodChannel('ai_crash_fix/backend');

/// Process handle used for quit / last-window-close teardown.
///
/// Kept outside Riverpod so we can SIGTERM/SIGKILL even if providers are mid-dispose.
/// On macOS, AppDelegate also kills this PID synchronously during
/// `applicationShouldTerminate` (Dart async stop is often too late).
class EmbeddedBackendLifecycle {
  static Process? _proc;
  static int? _pid;
  static bool _stopping = false;
  /// Unexpected exit restarts within a rolling window (survives notifier rebuilds).
  static int _autoRestartsInWindow = 0;
  static DateTime? _autoRestartWindowStart;

  static bool noteUnexpectedExitAndShouldRestart({int max = 3}) {
    final now = DateTime.now();
    final start = _autoRestartWindowStart;
    if (start == null || now.difference(start) > const Duration(minutes: 10)) {
      _autoRestartWindowStart = now;
      _autoRestartsInWindow = 0;
    }
    if (_autoRestartsInWindow >= max) return false;
    _autoRestartsInWindow += 1;
    return true;
  }

  static int get autoRestartsInWindow => _autoRestartsInWindow;

  static Future<void> _registerPidWithNative(int pid) async {
    if (!Platform.isMacOS) return;
    try {
      await _backendChannel.invokeMethod<void>('registerBackendPid', pid);
    } catch (_) {
      // Channel may be unavailable in tests; Swift side is best-effort.
    }
  }

  static Future<void> _clearPidWithNative() async {
    if (!Platform.isMacOS) return;
    try {
      await _backendChannel.invokeMethod<void>('clearBackendPid');
    } catch (_) {}
  }

  static Future<void> attach(Process proc) async {
    _proc = proc;
    _pid = proc.pid;
    await _registerPidWithNative(proc.pid);
  }

  static void clear(Process? proc) {
    if (proc == null || identical(_proc, proc)) {
      _proc = null;
      _pid = null;
    }
  }

  /// Graceful stop: SIGTERM → wait → SIGKILL. Safe to call multiple times.
  ///
  /// Keeps the native PID registered until kill finishes so AppDelegate can
  /// still SIGKILL during `applicationShouldTerminate` if we lose this race.
  static Future<void> stop() async {
    if (_stopping) return;
    _stopping = true;
    final proc = _proc;
    final pid = _pid ?? proc?.pid;
    _proc = null;
    _pid = null;
    if (proc == null && pid == null) {
      await _clearPidWithNative();
      _stopping = false;
      return;
    }
    try {
      if (proc != null) {
        proc.kill(ProcessSignal.sigterm);
      } else if (pid != null) {
        Process.killPid(pid, ProcessSignal.sigterm);
      }
      try {
        if (proc != null) {
          await proc.exitCode.timeout(const Duration(seconds: 2));
        } else {
          await Future<void>.delayed(const Duration(milliseconds: 400));
        }
      } on TimeoutException {
        try {
          if (proc != null) {
            proc.kill(ProcessSignal.sigkill);
          } else if (pid != null) {
            Process.killPid(pid, ProcessSignal.sigkill);
          }
        } catch (_) {}
        if (pid != null) {
          try {
            Process.killPid(-pid, ProcessSignal.sigkill);
          } catch (_) {}
        }
      }
      // Ask native side for a final sync kill if the process survived.
      if (Platform.isMacOS && pid != null) {
        try {
          await _backendChannel.invokeMethod<void>('terminateBackendNow');
        } catch (_) {}
      }
    } catch (_) {
      try {
        if (pid != null) Process.killPid(pid, ProcessSignal.sigkill);
      } catch (_) {}
    } finally {
      await _clearPidWithNative();
      _stopping = false;
    }
  }
}

class BackendProcessNotifier extends AsyncNotifier<BackendBoot?> {
  Process? _proc;
  StreamSubscription<String>? _out;
  StreamSubscription<String>? _err;
  http.Client? _client;
  final List<String> _logTail = <String>[];
  bool _intentionalStop = false;

  void _pushLog(String line) {
    final s = line.trimRight();
    if (s.isEmpty) return;
    _logTail.add(s);
    if (_logTail.length > 80) {
      _logTail.removeRange(0, _logTail.length - 80);
    }
  }

  @override
  Future<BackendBoot?> build() async {
    ref.onDispose(() {
      _intentionalStop = true;
      unawaited(_shutdown());
    });

    if (kIsWeb) return null;
    if (!Platform.isMacOS) return null;

    // Allow opting out (use external backend, e.g. local uvicorn).
    if ((Platform.environment['AI_CRASH_FIX_USE_EMBEDDED_BACKEND'] ?? '1') ==
        '0') {
      return null;
    }

    final backendPath = _resolveBackendPath();
    if (backendPath == null) {
      // Debug `flutter run -d macos`: no bundled binary — talk to external API.
      if (kDebugMode) return null;
      final exe = Platform.resolvedExecutable;
      final contentsDir = Directory(exe).parent.parent.path;
      final expected =
          '$contentsDir/Resources/backend/$kBackendProcessName/$kBackendProcessName';
      throw StateError(
        'Embedded backend binary not found at:\n$expected\n\n'
        'The DMG/app was likely built without re-signing after injecting the '
        'backend, or the install is incomplete. Rebuild with '
        './scripts/build_macos_dmg_all.sh, reinstall to /Applications, then '
        'run: xattr -cr "/Applications/Fixora.app"',
      );
    }

    final port = await _pickFreePort();
    final baseUrl = 'http://127.0.0.1:$port';

    _client = http.Client();
    _intentionalStop = false;

    final env = Map<String, String>.from(Platform.environment);
    env['AI_CRASH_FIX_HOST'] = '127.0.0.1';
    env['AI_CRASH_FIX_PORT'] = '$port';
    env['AI_CRASH_FIX_WEB_ROOT'] = '';
    // Parent-death watchdog in backend_main.py (Force Quit / missed SIGTERM).
    env['AI_CRASH_FIX_PARENT_PID'] = '$pid';

    final dataDir = _resolveDataDir();
    env['AI_CRASH_FIX_DATA_DIR'] = dataDir;

    final rgPath = _resolveRgPath();
    if (rgPath != null) {
      env['AI_CRASH_FIX_RG_PATH'] = rgPath;
    }

    final dbPath = (Platform.environment['AI_CRASH_FIX_DB_PATH'] ?? '').trim();
    if (dbPath.isNotEmpty) {
      env['AI_CRASH_FIX_DB_PATH'] = dbPath;
    }

    env['AI_CRASH_FIX_AUTO_LAUNCH_ENV'] = '1';
    _applyDefaultLaunchEnvFile(env);

    _proc = await Process.start(
      backendPath,
      ['--host', '127.0.0.1', '--port', '$port'],
      environment: env,
      runInShell: false,
    );
    await EmbeddedBackendLifecycle.attach(_proc!);

    _out = _proc!.stdout
        .transform(const SystemEncoding().decoder)
        .transform(const LineSplitter())
        .listen(_pushLog);
    _err = _proc!.stderr
        .transform(const SystemEncoding().decoder)
        .transform(const LineSplitter())
        .listen(_pushLog);

    // After boot, unexpected exits used to leave the UI on a dead port until
    // manual Retry. Watch exit and auto-restart a few times.
    final launched = _proc!;
    // ignore: unawaited_futures
    launched.exitCode.then((code) {
      if (_intentionalStop) return;
      EmbeddedBackendLifecycle.clear(launched);
      final tail = _logTail.isEmpty
          ? ''
          : '\n\n--- backend logs (tail) ---\n${_logTail.join('\n')}';
      final n = EmbeddedBackendLifecycle.autoRestartsInWindow + 1;
      if (EmbeddedBackendLifecycle.noteUnexpectedExitAndShouldRestart()) {
        debugPrint(
          'Embedded backend exited (code=$code); auto-restart $n/3$tail',
        );
        Future<void>.delayed(Duration(milliseconds: 400 * n), () {
          if (_intentionalStop) return;
          try {
            ref.invalidateSelf();
          } catch (_) {
            // Notifier already disposed (app quitting).
          }
        });
        return;
      }
      try {
        state = AsyncError(
          StateError(
            'Embedded backend exited with code $code after '
            '${EmbeddedBackendLifecycle.autoRestartsInWindow} auto-restarts.$tail',
          ),
          StackTrace.current,
        );
      } catch (_) {}
    });

    try {
      await _waitForHealth(baseUrl);
    } catch (e) {
      await _shutdown();
      rethrow;
    }

    return BackendBoot(baseUrl: baseUrl, port: port, backendPath: backendPath);
  }

  Future<void> _shutdown() async {
    _intentionalStop = true;
    await _out?.cancel();
    await _err?.cancel();
    _out = null;
    _err = null;
    _client?.close();
    _client = null;
    _proc = null;
    await EmbeddedBackendLifecycle.stop();
  }

  String? _resolveBackendPath() {
    final fromEnv =
        (Platform.environment['AI_CRASH_FIX_BACKEND_PATH'] ?? '').trim();
    if (fromEnv.isNotEmpty && File(fromEnv).existsSync()) return fromEnv;

    // Built macOS .app: .../Contents/MacOS/<exe> → .../Contents/Resources/...
    final exe = Platform.resolvedExecutable;
    final contentsDir = Directory(exe).parent.parent.path;
    final candidates = <String>[
      '$contentsDir/Resources/backend/$kBackendProcessName/$kBackendProcessName',
      // Pre-rebrand PyInstaller output
      '$contentsDir/Resources/backend/$kBackendProcessNameLegacy/$kBackendProcessNameLegacy',
    ];
    for (final candidate in candidates) {
      if (File(candidate).existsSync()) return candidate;
    }

    return null;
  }

  String _resolveDataDir() {
    final fromEnv =
        (Platform.environment['AI_CRASH_FIX_DATA_DIR'] ?? '').trim();
    if (fromEnv.isNotEmpty) return fromEnv;

    // Prefer the real user home — not a macOS App Sandbox container redirect.
    // Sandboxed builds resolve HOME under ~/Library/Containers/<bundle-id>/...,
    // which hides existing repos from previous non-sandboxed builds.
    final home = _realUserHome();
    if (home.isEmpty) {
      return Directory.systemTemp.path;
    }
    final dir = Directory('$home/Library/Application Support/Fixora');
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return dir.path;
  }

  /// Absolute home directory outside an App Sandbox container, when possible.
  String _realUserHome() {
    for (final key in ['AI_CRASH_FIX_REAL_HOME', 'HOME']) {
      final raw = (Platform.environment[key] ?? '').trim();
      if (raw.isEmpty) continue;
      if (!raw.contains('/Library/Containers/')) return raw;
    }
    // Fall back: strip .../Library/Containers/<id>/Data from a container HOME.
    final home = (Platform.environment['HOME'] ?? '').trim();
    final marker = '/Library/Containers/';
    final idx = home.indexOf(marker);
    if (idx > 0) {
      return home.substring(0, idx);
    }
    return home;
  }

  static const _defaultLaunchEnvFileName = 'crash_fix_gosi_brain_conf.env';

  /// Auto-load ~/crash_fix_gosi_brain_conf.env when present (macOS standalone).
  void _applyDefaultLaunchEnvFile(Map<String, String> env) {
    if ((env['AI_CRASH_FIX_ENV_FILE'] ?? '').trim().isNotEmpty) return;
    final home = _realUserHome();
    if (home.isEmpty) return;
    final candidate = '$home/$_defaultLaunchEnvFileName';
    final file = File(candidate);
    if (!file.existsSync() || !_envFileNonempty(file)) return;
    env['AI_CRASH_FIX_ENV_FILE'] = candidate;
  }

  bool _envFileNonempty(File file) {
    try {
      for (final rawLine in file.readAsLinesSync()) {
        var line = rawLine.trim();
        if (line.isEmpty || line.startsWith('#')) continue;
        if (line.startsWith('export ')) {
          line = line.substring(7).trim();
        }
        final eq = line.indexOf('=');
        if (eq <= 0) continue;
        final key = line.substring(0, eq).trim();
        final val = line.substring(eq + 1).trim();
        if (key.isNotEmpty && val.isNotEmpty) return true;
      }
    } catch (_) {}
    return false;
  }

  String? _resolveRgPath() {
    final fromEnv =
        (Platform.environment['AI_CRASH_FIX_RG_PATH'] ?? '').trim();
    if (fromEnv.isNotEmpty && File(fromEnv).existsSync()) return fromEnv;

    final exe = Platform.resolvedExecutable;
    final contentsDir = Directory(exe).parent.parent.path;
    final candidate = '$contentsDir/Resources/bin/rg';
    if (File(candidate).existsSync()) return candidate;
    return null;
  }

  Future<int> _pickFreePort() async {
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = socket.port;
    await socket.close();
    return port;
  }

  Future<void> _waitForHealth(String baseUrl) async {
    final deadline = DateTime.now().add(const Duration(seconds: 25));
    Object? lastErr;
    while (DateTime.now().isBefore(deadline)) {
      if (_intentionalStop) {
        throw StateError('Backend startup cancelled');
      }
      try {
        final res = await _client!
            .get(Uri.parse('$baseUrl/api/health'))
            .timeout(const Duration(seconds: 3));
        if (res.statusCode >= 200 && res.statusCode < 300) return;
        lastErr = 'status=${res.statusCode}';
      } catch (e) {
        lastErr = e;
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    final tail = _logTail.isEmpty
        ? ''
        : '\n\n--- backend logs (tail) ---\n${_logTail.join('\n')}';
    throw StateError('Backend did not become healthy in time: $lastErr$tail');
  }
}

final backendProcessProvider =
    AsyncNotifierProvider<BackendProcessNotifier, BackendBoot?>(
  BackendProcessNotifier.new,
);
