import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';

class ApiClient {
  ApiClient({http.Client? client, String? baseUrl})
    : _client = client ?? http.Client(),
      _baseUri = Uri.parse(baseUrl ?? AppConfig.apiBaseUrl);

  final http.Client _client;
  final Uri _baseUri;

  Future<http.Response> get(String path) {
    return _client.get(_resolve(path)).timeout(AppConfig.requestTimeout);
  }

  Future<http.Response> postJson(
    String path, {
    Map<String, Object?> body = const {},
  }) {
    return _client
        .post(
          _resolve(path),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode(body),
        )
        .timeout(AppConfig.requestTimeout);
  }

  Uri _resolve(String path) {
    return _baseUri.resolve(path.startsWith('/') ? path.substring(1) : path);
  }

  void close() {
    _client.close();
  }
}
