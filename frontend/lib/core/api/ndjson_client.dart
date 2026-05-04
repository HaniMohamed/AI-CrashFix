import 'dart:async';
import 'dart:convert';

import 'api_client.dart';

/// Issue a streaming POST and yield each NDJSON line as a parsed JSON map.
///
/// One JSON object per line; blank lines are ignored.
Stream<Map<String, dynamic>> streamNdjsonPost(
  ApiClient client,
  String path, {
  Map<String, dynamic>? body,
}) async* {
  final response = await client.streamPost(path, body: body);
  if (response.statusCode != 200) {
    final raw = await response.stream.bytesToString();
    throw ApiException(response.statusCode, raw);
  }

  final lineStream = response.stream
      .transform(utf8.decoder)
      .transform(const LineSplitter());

  await for (final line in lineStream) {
    if (line.trim().isEmpty) continue;
    try {
      final obj = jsonDecode(line);
      if (obj is Map<String, dynamic>) yield obj;
    } catch (_) {
      // Skip lines that aren't valid JSON (defensive; backend always emits valid lines).
    }
  }
}
