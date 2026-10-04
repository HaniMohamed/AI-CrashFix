import 'api_client.dart';
import 'endpoints.dart';

String _messageFromResponse(dynamic res) {
  if (res is Map) {
    final msg = res['message']?.toString();
    if (msg != null && msg.isNotEmpty) return msg;
    if (res['ok'] == true) return 'Connected successfully.';
  }
  return 'Connected successfully.';
}

Future<String> testStoreConnectivity(
  ApiClient api, {
  required String backend,
  String? dbUrl,
  String? username,
  String? password,
  String? userId,
}) async {
  final res = await api.postJson(
    Endpoints.setupTestStore,
    body: {
      'backend': backend,
      if (dbUrl != null && dbUrl.isNotEmpty) 'db_url': dbUrl,
      if (username != null && username.isNotEmpty) 'username': username,
      if (password != null && password.isNotEmpty) 'password': password,
      if (userId != null && userId.isNotEmpty) 'user_id': userId,
    },
  );
  return _messageFromResponse(res);
}

Future<String> testLlmConnectivity(
  ApiClient api, {
  required Map<String, dynamic> body,
}) async {
  final res = await api.postJson(Endpoints.settingsTestLlm, body: body);
  return _messageFromResponse(res);
}

Future<String> testJiraConnectivity(
  ApiClient api, {
  required Map<String, dynamic> body,
}) async {
  final res = await api.postJson(Endpoints.settingsTestJira, body: body);
  return _messageFromResponse(res);
}

Future<String> testGitlabConnectivity(
  ApiClient api, {
  required Map<String, dynamic> body,
}) async {
  final res = await api.postJson(Endpoints.settingsTestGitlab, body: body);
  return _messageFromResponse(res);
}
