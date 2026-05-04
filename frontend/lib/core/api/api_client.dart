import 'dart:convert';

import 'package:fetch_client/fetch_client.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Thin JSON wrapper around `package:http`.
///
/// On Flutter web we use [FetchClient] so streaming responses (NDJSON) read
/// from the browser fetch ReadableStream. Off-web we use the default
/// [http.Client] which already streams.
class ApiClient {
  ApiClient({required this.baseUrl, http.Client? client})
      : _client = client ?? _defaultClient();

  final String baseUrl;
  final http.Client _client;

  static http.Client _defaultClient() {
    if (kIsWeb) {
      // streamRequests: true ensures POST body is sent and the response body
      // is exposed as a real Stream<List<int>>.
      return FetchClient(mode: RequestMode.cors, streamRequests: true);
    }
    return http.Client();
  }

  Uri _uri(String path, [Map<String, dynamic>? query]) {
    final base = Uri.parse(baseUrl);
    final qp = <String, String>{
      ...base.queryParameters,
      if (query != null)
        for (final e in query.entries)
          if (e.value != null) e.key: e.value.toString(),
    };
    return base.replace(
      path: '${base.path.replaceAll(RegExp(r"/$"), "")}$path',
      queryParameters: qp.isEmpty ? null : qp,
    );
  }

  Future<dynamic> getJson(String path, {Map<String, dynamic>? query}) async {
    final res = await _client.get(_uri(path, query));
    return _decodeOrThrow(res);
  }

  Future<dynamic> postJson(String path, {Map<String, dynamic>? body}) async {
    final res = await _client.post(
      _uri(path),
      headers: const {'content-type': 'application/json'},
      body: body == null ? null : jsonEncode(body),
    );
    return _decodeOrThrow(res);
  }

  /// Issue a streaming POST and return the raw [http.StreamedResponse]; the
  /// caller is responsible for consuming `response.stream`.
  Future<http.StreamedResponse> streamPost(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final req = http.Request('POST', _uri(path))
      ..headers['content-type'] = 'application/json'
      ..headers['accept'] = 'application/x-ndjson';
    if (body != null) {
      req.body = jsonEncode(body);
    }
    return _client.send(req);
  }

  dynamic _decodeOrThrow(http.Response res) {
    if (res.statusCode >= 200 && res.statusCode < 300) {
      if (res.bodyBytes.isEmpty) return null;
      return jsonDecode(utf8.decode(res.bodyBytes));
    }
    String message = res.body;
    try {
      final j = jsonDecode(res.body);
      if (j is Map && j['detail'] != null) message = j['detail'].toString();
    } catch (_) {}
    throw ApiException(res.statusCode, message);
  }

  void close() => _client.close();
}

class ApiException implements Exception {
  final int statusCode;
  final String message;
  ApiException(this.statusCode, this.message);
  @override
  String toString() => 'ApiException($statusCode): $message';
}
