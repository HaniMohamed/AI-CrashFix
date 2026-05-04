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

  static String relative(String? iso) {
    if (iso == null || iso.isEmpty) return '';
    DateTime dt;
    try {
      dt = DateTime.parse(iso);
    } catch (_) {
      return iso;
    }
    if (dt.isUtc == false) dt = dt.toUtc();
    final diff = DateTime.now().toUtc().difference(dt);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return DateFormat('MMM d, y').format(dt.toLocal());
  }

  static String shortDate(String iso) {
    try {
      return DateFormat('MMM d').format(DateTime.parse(iso));
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
