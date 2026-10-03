import 'dart:convert';

import 'package:fairest_one/core/network/api_client.dart';
import 'package:fairest_one/features/mirror/data/mirror_gateway_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('sends a structured command to the future mirror API', () async {
    final httpClient = MockClient((request) async {
      expect(
        request.url.toString(),
        'http://127.0.0.1:8080/api/v1/mirror/commands',
      );
      expect(jsonDecode(request.body), {'command': 'led_on'});
      return http.Response('{}', 202);
    });
    final gateway = MirrorGatewayClient(
      apiClient: ApiClient(
        client: httpClient,
        baseUrl: 'http://127.0.0.1:8080/',
      ),
    );

    final response = await gateway.sendCommand(MirrorCommand.ledOn);

    expect(response.statusCode, 202);
    gateway.close();
  });
}
