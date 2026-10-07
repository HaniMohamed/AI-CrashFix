import 'package:intl/intl.dart';

class Fmt {
  Fmt._();

  static String compactInt(int v) {
    if (v.abs() >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
    if (v.abs() >= 10000) return '${(v / 1000).toStringAsFixed(1)}k';
    return NumberFormat.decimalPattern().format(v);
  }

  static String percent(double v, {int digits = 0}) =>
      '${(v * 100).toStringAsFixed(digits)}%';

  static String duration(double seconds) {
    if (seconds < 1) return '${(seconds * 1000).round()} ms';
    if (seconds < 60) return '${seconds.toStringAsFixed(1)}s';
    final m = seconds ~/ 60;
    final s = seconds.round() - (m * 60);
    if (m < 60) return '${m}m ${s}s';
    final h = m ~/ 60;
    return '${h}h ${m % 60}m';
  }

  /// Parses an ISO timestamp from the backend. Backend timestamps are
  /// always UTC; if the string has no timezone suffix (no `Z`/offset),
  /// `DateTime.parse` would otherwise treat it as local time, so we
  /// normalize those naive strings to be parsed as UTC explicitly.
  static DateTime _parseUtc(String iso) {
    final hasOffset = RegExp(r'(Z|[+-]\d{2}:?\d{2})$').hasMatch(iso);
    final dt = DateTime.parse(hasOffset ? iso : '${iso}Z');
    return dt.isUtc ? dt : dt.toUtc();
  }

  static String relative(String? iso) {
    if (iso == null || iso.isEmpty) return '';
    DateTime dt;
    try {
      dt = _parseUtc(iso);
    } catch (_) {
      return iso;
    }
    final diff = DateTime.now().toUtc().difference(dt);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return DateFormat('MMM d, y').format(dt.toLocal());
  }

  /// Human-readable absolute datetime, e.g. ``Jul 19, 2026 · 3:20 PM``.
  static String readableDateTime(String? iso) {
    if (iso == null || iso.isEmpty) return '';
    try {
      final dt = _parseUtc(iso).toLocal();
      return DateFormat('MMM d, y · h:mm a').format(dt);
    } catch (_) {
      return iso;
    }
  }

  static String shortDate(String iso) {
    try {
      return DateFormat('MMM d').format(_parseUtc(iso).toLocal());
    } catch (_) {
      return iso;
    }
  }

  static String shortId(String? id, {int head = 6, int tail = 4}) {
    if (id == null || id.isEmpty) return '';
    if (id.length <= head + tail + 1) return id;
    return '${id.substring(0, head)}…${id.substring(id.length - tail)}';
  }
}
