import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/endpoints.dart';
import 'api_provider.dart';

/// ``backend`` or ``launcher``.
typedef LogSource = String;

class LogViewerState {
  final String source;
  final String content;
  final int nextOffset;
  final int size;
  final String path;
  final String? dataDir;
  final bool available;
  final bool truncated;
  final String? message;
  final bool followTail;
  final bool autoRefresh;

  const LogViewerState({
    required this.source,
    this.content = '',
    this.nextOffset = 0,
    this.size = 0,
    this.path = '',
    this.dataDir,
    this.available = false,
    this.truncated = false,
    this.message,
    this.followTail = true,
    this.autoRefresh = true,
  });

  LogViewerState copyWith({
    String? content,
    int? nextOffset,
    int? size,
    String? path,
    String? dataDir,
    bool? available,
    bool? truncated,
    String? message,
    bool? followTail,
    bool? autoRefresh,
    bool appendContent = false,
  }) {
    final merged = appendContent && content != null
        ? (this.content + content)
        : (content ?? this.content);
    return LogViewerState(
      source: source,
      content: merged,
      nextOffset: nextOffset ?? this.nextOffset,
      size: size ?? this.size,
      path: path ?? this.path,
      dataDir: dataDir ?? this.dataDir,
      available: available ?? this.available,
      truncated: truncated ?? this.truncated,
      message: message ?? this.message,
      followTail: followTail ?? this.followTail,
      autoRefresh: autoRefresh ?? this.autoRefresh,
    );
  }
}

class LogViewerNotifier extends FamilyNotifier<LogViewerState, LogSource> {
  Timer? _timer;

  @override
  LogViewerState build(LogSource source) {
    ref.onDispose(_stopTimer);
    Future.microtask(() => refresh());
    _syncTimer();
    return LogViewerState(source: source);
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  void _syncTimer() {
    _stopTimer();
    if (!state.autoRefresh) return;
    _timer = Timer.periodic(const Duration(seconds: 2), (_) {
      poll();
    });
  }

  Future<void> refresh() async {
    state = LogViewerState(
      source: arg,
      followTail: state.followTail,
      autoRefresh: state.autoRefresh,
    );
    await poll(fromStart: true);
  }

  Future<void> poll({bool fromStart = false}) async {
    final api = ref.read(apiClientProvider);
    final offset = fromStart || !state.followTail ? 0 : state.nextOffset;
    try {
      final res = await api.getJson(
        Endpoints.logTail(arg),
        query: {
          'offset': offset,
          'tail': state.followTail,
        },
      );
      if (res is! Map) return;
      final m = res.cast<String, dynamic>();
      final chunk = (m['content'] ?? '').toString();
      final append = !fromStart && state.followTail && offset > 0 && chunk.isNotEmpty;
      state = state.copyWith(
        content: chunk,
        appendContent: append,
        nextOffset: (m['next_offset'] as num?)?.toInt() ?? 0,
        size: (m['size'] as num?)?.toInt() ?? 0,
        path: (m['path'] ?? '').toString(),
        dataDir: m['data_dir']?.toString(),
        available: m['available'] == true,
        truncated: m['truncated'] == true,
        message: m['message']?.toString(),
      );
    } catch (e) {
      state = state.copyWith(
        available: false,
        message: e.toString(),
      );
    }
  }

  void setFollowTail(bool value) {
    state = state.copyWith(followTail: value);
    if (value) {
      refresh();
    }
  }

  void setAutoRefresh(bool value) {
    state = state.copyWith(autoRefresh: value);
    _syncTimer();
  }
}

final logViewerProvider =
    NotifierProvider.family<LogViewerNotifier, LogViewerState, LogSource>(
  LogViewerNotifier.new,
);
