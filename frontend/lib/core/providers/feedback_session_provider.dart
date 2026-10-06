import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../api/endpoints.dart';
import '../models/run_event.dart';
import 'api_provider.dart';

/// Mirrors a row in the `crash_feedback` table / `GET .../feedback` history.
class FeedbackMessage {
  final int? id;
  final String crashId;
  final String role;
  final String message;
  final String status;
  final int? iteration;
  final String? createdAt;

  const FeedbackMessage({
    this.id,
    required this.crashId,
    required this.role,
    required this.message,
    required this.status,
    this.iteration,
    this.createdAt,
  });

  factory FeedbackMessage.fromJson(Map<String, dynamic> j) => FeedbackMessage(
        id: (j['id'] as num?)?.toInt(),
        crashId: (j['crash_id'] ?? '').toString(),
        role: (j['role'] ?? 'system').toString(),
        message: (j['message'] ?? '').toString(),
        status: (j['status'] ?? 'info').toString(),
        iteration: (j['iteration'] as num?)?.toInt(),
        createdAt: j['created_at']?.toString(),
      );

  bool get isUser => role == 'user';
  bool get isAi => role == 'ai';
  bool get isValid => status == 'valid' || status == 'applied';
  bool get isInvalid => status == 'invalid' || status == 'error';
  bool get isAnswer => status == 'answered';
}

class FeedbackHistory {
  final List<FeedbackMessage> messages;
  final int feedbackIterationCount;
  final bool feedbackLocked;

  const FeedbackHistory({
    this.messages = const [],
    this.feedbackIterationCount = 0,
    this.feedbackLocked = false,
  });

  factory FeedbackHistory.fromJson(Map<String, dynamic> j) => FeedbackHistory(
        messages: (j['messages'] as List? ?? const [])
            .whereType<Map>()
            .map((e) => FeedbackMessage.fromJson(e.cast<String, dynamic>()))
            .toList(),
        feedbackIterationCount:
            (j['feedback_iteration_count'] as num?)?.toInt() ?? 0,
        feedbackLocked: j['feedback_locked'] == true,
      );
}

final crashFeedbackHistoryProvider = FutureProvider.autoDispose
    .family<FeedbackHistory, String>((ref, crashId) async {
  final api = ref.watch(apiClientProvider);
  final res = await api.getJson(Endpoints.crashFeedback(crashId));
  return FeedbackHistory.fromJson((res as Map).cast<String, dynamic>());
});

/// Summary carried by the final NDJSON line of a successful regeneration.
class FeedbackRegenerationSummary {
  final String? prUrl;
  final String? prBody;
  final int? filesChanged;
  final int? additions;
  final int? deletions;

  const FeedbackRegenerationSummary({
    this.prUrl,
    this.prBody,
    this.filesChanged,
    this.additions,
    this.deletions,
  });

  factory FeedbackRegenerationSummary.fromJson(Map<String, dynamic> j) {
    final stats = (j['stats'] as Map?)?.cast<String, dynamic>() ?? const {};
    return FeedbackRegenerationSummary(
      prUrl: j['pr_url']?.toString(),
      prBody: j['pr_body']?.toString(),
      filesChanged: (stats['files_changed'] as num?)?.toInt(),
      additions: (stats['additions'] as num?)?.toInt(),
      deletions: (stats['deletions'] as num?)?.toInt(),
    );
  }
}

enum FeedbackStreamStatus { idle, sending, streaming, done, rejected, failed }

class FeedbackSessionState {
  final FeedbackStreamStatus status;
  final List<FeedbackMessage> messages;
  final List<RunEvent> progressEvents;
  final FeedbackRegenerationSummary? summary;
  final String? error;

  const FeedbackSessionState({
    this.status = FeedbackStreamStatus.idle,
    this.messages = const [],
    this.progressEvents = const [],
    this.summary,
    this.error,
  });

  bool get isActive =>
      status == FeedbackStreamStatus.sending ||
      status == FeedbackStreamStatus.streaming;

  FeedbackSessionState copyWith({
    FeedbackStreamStatus? status,
    List<FeedbackMessage>? messages,
    List<RunEvent>? progressEvents,
    FeedbackRegenerationSummary? summary,
    String? error,
  }) =>
      FeedbackSessionState(
        status: status ?? this.status,
        messages: messages ?? this.messages,
        progressEvents: progressEvents ?? this.progressEvents,
        summary: summary ?? this.summary,
        error: error ?? this.error,
      );
}

/// Modeled on `RunSessionNotifier`: POSTs a feedback note and handles both
/// response shapes the backend may return — an immediate JSON rejection, or
/// an NDJSON stream of the same event envelope used by `POST /api/runs`.
class FeedbackSessionNotifier extends FamilyNotifier<FeedbackSessionState, String> {
  StreamSubscription? _sub;

  @override
  FeedbackSessionState build(String crashId) {
    ref.onDispose(() => _sub?.cancel());
    return const FeedbackSessionState();
  }

  Future<void> sendNote(String note) async {
    await _sub?.cancel();
    final client = ref.read(apiClientProvider);
    state = state.copyWith(
      status: FeedbackStreamStatus.sending,
      progressEvents: const [],
      summary: null,
      error: null,
    );

    try {
      final response = await client.streamPost(
        Endpoints.crashFeedback(arg),
        body: {'note': note, 'locale': _deviceLanguageCode()},
      );

      if (response.statusCode == 409) {
        final raw = await response.stream.bytesToString();
        state = state.copyWith(
          status: FeedbackStreamStatus.failed,
          error: raw.isEmpty ? 'Feedback is locked (regeneration in flight).' : raw,
        );
        return;
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final raw = await response.stream.bytesToString();
        throw ApiException(response.statusCode, raw);
      }

      final contentType =
          response.headers['content-type'] ?? response.headers['Content-Type'] ?? '';

      if (!contentType.contains('ndjson')) {
        await response.stream.drain<void>();
        _handleNonStreamingResponse();
        return;
      }

      state = state.copyWith(status: FeedbackStreamStatus.streaming);
      final lineStream = response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter());

      _sub = lineStream.listen(
        _handleLine,
        onError: (Object e, StackTrace _) {
          state = state.copyWith(
            status: FeedbackStreamStatus.failed,
            error: e.toString(),
          );
        },
        onDone: () {
          if (state.status == FeedbackStreamStatus.streaming) {
            state = state.copyWith(status: FeedbackStreamStatus.done);
          }
        },
        cancelOnError: false,
      );
    } catch (e) {
      state = state.copyWith(
        status: FeedbackStreamStatus.failed,
        error: e.toString(),
      );
    }
  }

  /// The backend persists the user note and its AI verdict/answer as `crash_feedback`
  /// rows before this response is even sent, and `_send()` refetches history right
  /// after `sendNote()` resolves — so this response body only needs to flip the
  /// status; the actual message content comes from `crashFeedbackHistoryProvider`,
  /// not from here (keeping one source of truth instead of showing it twice).
  void _handleNonStreamingResponse() {
    state = state.copyWith(status: FeedbackStreamStatus.rejected);
  }

  void _handleLine(String line) {
    if (line.trim().isEmpty) return;
    Map<String, dynamic>? obj;
    try {
      final decoded = jsonDecode(line);
      if (decoded is Map) obj = decoded.cast<String, dynamic>();
    } catch (_) {
      return;
    }
    if (obj == null) return;

    if (obj['type'] == 'feedback_summary') {
      state = state.copyWith(
        status: FeedbackStreamStatus.done,
        summary: FeedbackRegenerationSummary.fromJson(obj),
      );
      return;
    }

    final ev = RunEvent.fromJson(obj);
    state = state.copyWith(progressEvents: [...state.progressEvents, ev]);
    if (ev is ErrorEvent) {
      state = state.copyWith(status: FeedbackStreamStatus.failed, error: ev.message);
    }
  }

  Future<void> cancel() async {
    await _sub?.cancel();
    _sub = null;
  }

  void reset() {
    _sub?.cancel();
    _sub = null;
    state = const FeedbackSessionState();
  }
}

final feedbackSessionProvider = NotifierProvider.family<FeedbackSessionNotifier,
    FeedbackSessionState, String>(FeedbackSessionNotifier.new);

/// Backend message localization follows the device locale (currently en/ar);
/// the app itself has no in-UI language switcher yet.
String _deviceLanguageCode() {
  try {
    return ui.PlatformDispatcher.instance.locale.languageCode;
  } catch (_) {
    return 'en';
  }
}
