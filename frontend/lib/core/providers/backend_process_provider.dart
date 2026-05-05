import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

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

class BackendProcessNotifier extends AsyncNotifier<BackendBoot?> {
  Process? _proc;
  StreamSubscription<String>? _out;
  StreamSubscription<String>? _err;
  http.Client? _client;
  final List<String> _logTail = <String>[];

  void _pushLog(String line) {
    final s = line.trimRight();
    if (s.isEmpty) return;
    _logTail.add(s);
    // Keep last ~80 lines.
    if (_logTail.length > 80) {
      _logTail.removeRange(0, _logTail.length - 80);
    }
  }

  @override
  Future<BackendBoot?> build() async {
    ref.onDispose(() async {
      await _out?.cancel();
      await _err?.cancel();
      _client?.close();
      _client = null;
      try {
        _proc?.kill(ProcessSignal.sigterm);
      } catch (_) {}
      _proc = null;
    });

    if (kIsWeb) return null;
    if (!Platform.isMacOS) return null;

    // Allow opting out (use external backend).
    if ((Platform.environment['AI_CRASH_FIX_USE_EMBEDDED_BACKEND'] ?? '1') == '0') {
      return null;
    }

    final backendPath = _resolveBackendPath();
    if (backendPath == null) {
      throw StateError(
        'Embedded backend binary not found. Set AI_CRASH_FIX_BACKEND_PATH or stage it under the app bundle Resources/backend/.',
      );
    }

    final port = await _pickFreePort();
    final baseUrl = 'http://127.0.0.1:$port';

    _client = http.Client();

    final env = Map<String, String>.from(Platform.environment);
    env['AI_CRASH_FIX_HOST'] = '127.0.0.1';
    env['AI_CRASH_FIX_PORT'] = '$port';

    // If caller provided a DB path, forward it.
    final dbPath = (Platform.environment['AI_CRASH_FIX_DB_PATH'] ?? '').trim();
    if (dbPath.isNotEmpty) {
      env['AI_CRASH_FIX_DB_PATH'] = dbPath;
    }

    _proc = await Process.start(
      backendPath,
      const [],
      environment: env,
      runInShell: false,
    );

    _out = _proc!.stdout
        .transform(const SystemEncoding().decoder)
        .transform(const LineSplitter())
        .listen(_pushLog);
    _err = _proc!.stderr
        .transform(const SystemEncoding().decoder)
        .transform(const LineSplitter())
        .listen(_pushLog);

    // Wait until backend is ready.
    await _waitForHealth(baseUrl);

    return BackendBoot(baseUrl: baseUrl, port: port, backendPath: backendPath);
  }

  String? _resolveBackendPath() {
    final fromEnv = (Platform.environment['AI_CRASH_FIX_BACKEND_PATH'] ?? '').trim();
    if (fromEnv.isNotEmpty && File(fromEnv).existsSync()) return fromEnv;

    // In a built macOS .app, resolvedExecutable points to:
    //   .../MyApp.app/Contents/MacOS/MyApp
    // Resources are at:
    //   .../MyApp.app/Contents/Resources/
    final exe = Platform.resolvedExecutable;
    final contentsDir = Directory(exe).parent.parent.path; // .../Contents
    final candidate =
        '$contentsDir/Resources/backend/ai_crash_fix_backend/ai_crash_fix_backend';
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
    final deadline = DateTime.now().add(const Duration(seconds: 20));
    Object? lastErr;
    var exitHooked = false;
    while (DateTime.now().isBefore(deadline)) {
      // If the process died, surface it.
      final p = _proc;
      if (p != null && !exitHooked) {
        exitHooked = true;
        final code = p.exitCode;
        // ignore: unawaited_futures
        code.then((c) {
          if (c != 0 && state.isLoading) {
            final tail = _logTail.isEmpty ? '' : '\n\n--- backend logs (tail) ---\n${_logTail.join('\n')}';
            state = AsyncError(
              StateError('Backend exited with code $c$tail'),
              StackTrace.current,
            );
          }
        });
      }

      try {
        final res = await _client!.get(Uri.parse('$baseUrl/api/health'));
        if (res.statusCode >= 200 && res.statusCode < 300) return;
        lastErr = 'status=${res.statusCode}';
      } catch (e) {
        lastErr = e;
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    throw StateError('Backend did not become healthy in time: $lastErr');
  }
}

final backendProcessProvider =
    AsyncNotifierProvider<BackendProcessNotifier, BackendBoot?>(
  BackendProcessNotifier.new,
);

