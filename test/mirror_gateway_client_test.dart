import 'dart:convert';

import 'package:fairest_one/core/config/app_config.dart';
import 'package:fairest_one/core/network/api_client.dart';
import 'package:fairest_one/features/mirror/data/mirror_gateway_client.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  setUp(() {
    dotenv.loadFromString(
      envString: '''
API_BASE_URL=http://127.0.0.1:8080/
WS_BASE_URL=ws://127.0.0.1:8080/ws
MIRROR_DEVICE_ID=test-mirror
USE_MOCK_IOT=false
REQUEST_TIMEOUT_SECONDS=3
SUPABASE_URL=https://test-project.supabase.co
SUPABASE_PUBLISHABLE_KEY=sb_publishable_test
USE_SUPABASE=false
''',
    );
  });

  tearDown(dotenv.clean);

  test('reads the Raspberry Pi configuration', () {
    expect(AppConfig.apiBaseUrl, 'http://127.0.0.1:8080/');
    expect(AppConfig.webSocketUrl, 'ws://127.0.0.1:8080/ws');
    expect(AppConfig.mirrorDeviceId, 'test-mirror');
    expect(AppConfig.useMockIot, isFalse);
    expect(AppConfig.requestTimeout, const Duration(seconds: 3));
    expect(AppConfig.supabaseUrl, 'https://test-project.supabase.co');
    expect(AppConfig.supabasePublishableKey, 'sb_publishable_test');
    expect(AppConfig.useSupabase, isFalse);
  });

  test('sends a structured command to the mirror gateway', () async {
    final httpClient = MockClient((request) async {
      expect(request.method, 'POST');
      expect(
        request.url.toString(),
        'http://127.0.0.1:8080/api/v1/mirror/commands',
      );
      expect(request.headers['content-type'], 'application/json');
      expect(jsonDecode(request.body), {
        'deviceId': 'test-mirror',
        'command': 'led_on',
      });
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
