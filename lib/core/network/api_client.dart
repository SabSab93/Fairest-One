import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';

class ApiClient {
  ApiClient({http.Client? client, String? baseUrl})
    : _client = client ?? http.Client(),
      _baseUri = _parseBaseUri(baseUrl ?? AppConfig.apiBaseUrl);

  final http.Client _client;
  final Uri _baseUri;

  Future<http.Response> get(
    String path, {
    Map<String, String> headers = const {},
  }) {
    return _client
        .get(_resolve(path), headers: headers)
        .timeout(AppConfig.requestTimeout);
  }

  Future<http.Response> postJson(
    String path, {
    Map<String, Object?> body = const {},
    Map<String, String> headers = const {},
  }) {
    return _client
        .post(
          _resolve(path),
          headers: {'Content-Type': 'application/json', ...headers},
          body: jsonEncode(body),
        )
        .timeout(AppConfig.requestTimeout);
  }

  Uri _resolve(String path) {
    return _baseUri.resolve(path.startsWith('/') ? path.substring(1) : path);
  }

  static Uri _parseBaseUri(String value) {
    final uri = Uri.parse(value);
    return uri.hasScheme ? uri : Uri.base.resolveUri(uri);
  }

  void close() {
    _client.close();
  }
}
