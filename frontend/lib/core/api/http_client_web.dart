import 'package:fetch_client/fetch_client.dart';
import 'package:http/http.dart' as http;

/// Web: [FetchClient] so NDJSON responses stream via fetch ReadableStream.
http.Client createHttpClient() {
  // IMPORTANT: `streamRequests: true` uses a duplex fetch body, which
  // Chromium only allows over HTTP/2 or HTTP/3. Uvicorn (and most local
  // dev servers) speak HTTP/1.1, so the browser throws
  // `TypeError: Failed to fetch` on POST /api/runs.
  //
  // `streamRequests: false` still buffers only the *request* body (tiny
  // JSON here); the *response* is still read as a stream, so NDJSON works.
  return FetchClient(mode: RequestMode.cors, streamRequests: false);
}
