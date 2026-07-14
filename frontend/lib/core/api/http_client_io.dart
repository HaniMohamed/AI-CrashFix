import 'package:http/http.dart' as http;

/// IO / desktop: default [http.Client] already streams responses.
http.Client createHttpClient() => http.Client();
