import 'dart:convert';

import 'package:http/http.dart' as http;

import 'http_client_io.dart' if (dart.library.html) 'http_client_web.dart';

/// Thin JSON wrapper around `package:http`.
///
/// On Flutter web we use FetchClient so streaming responses (NDJSON) read
/// from the browser fetch ReadableStream. Off-web we use the default
/// [http.Client] which already streams.
class ApiClient {
  ApiClient({
    required this.baseUrl,
    http.Client? client,
    this.authToken,
    this.onUnauthorized,
  }) : _client = client ?? createHttpClient();

  final String baseUrl;
  final String? authToken;
  final void Function()? onUnauthorized;
  final http.Client _client;

  Map<String, String> _headers({bool json = true}) {
    final headers = <String, String>{};
    if (json) headers['content-type'] = 'application/json';
    final token = authToken?.trim();
    if (token != null && token.isNotEmpty) {
      headers['authorization'] = 'Bearer $token';
    }
    return headers;
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
    final res = await _client.get(_uri(path, query), headers: _headers());
    return _decodeOrThrow(res);
  }

  Future<dynamic> postJson(String path, {Map<String, dynamic>? body}) async {
    final res = await _client.post(
      _uri(path),
      headers: _headers(),
      body: body == null ? null : jsonEncode(body),
    );
    return _decodeOrThrow(res);
  }

  Future<dynamic> patchJson(String path, {Map<String, dynamic>? body}) async {
    final res = await _client.patch(
      _uri(path),
      headers: _headers(),
      body: body == null ? null : jsonEncode(body),
    );
    return _decodeOrThrow(res);
  }

  /// Multipart upload (e.g. `POST /api/settings/google_credentials` with field `file`).
  Future<dynamic> postMultipartFile(
    String path, {
    required List<int> bytes,
    required String filename,
    String fieldName = 'file',
  }) async {
    final req = http.MultipartRequest('POST', _uri(path))
      ..headers.addAll(_headers(json: false));
    req.files.add(
      http.MultipartFile.fromBytes(
        fieldName,
        bytes,
        filename: filename,
      ),
    );
    final streamed = await _client.send(req);
    final res = await http.Response.fromStream(streamed);
    return _decodeOrThrow(res);
  }

  Future<dynamic> deleteJson(String path, {Map<String, dynamic>? body}) async {
    final req = http.Request('DELETE', _uri(path))
      ..headers.addAll(_headers());
    if (body != null) {
      req.body = jsonEncode(body);
    }
    final streamed = await _client.send(req);
    final res = await http.Response.fromStream(streamed);
    return _decodeOrThrow(res);
  }

  /// Issue a streaming POST and return the raw [http.StreamedResponse]; the
  /// caller is responsible for consuming `response.stream`.
  Future<http.StreamedResponse> streamPost(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final req = http.Request('POST', _uri(path))
      ..headers.addAll(_headers())
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
    if (res.statusCode == 401) {
      onUnauthorized?.call();
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
