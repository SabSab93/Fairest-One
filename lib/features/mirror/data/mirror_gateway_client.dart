import 'package:http/http.dart' as http;

import '../../../core/config/app_config.dart';
import '../../../core/network/api_client.dart';

enum MirrorCommand {
  ledOn('led_on'),
  ledOff('led_off'),
  startCapture('start_capture');

  const MirrorCommand(this.value);

  final String value;
}

class MirrorGatewayClient {
  MirrorGatewayClient({ApiClient? apiClient})
    : _apiClient = apiClient ?? ApiClient();

  final ApiClient _apiClient;

  Future<bool> healthCheck() async {
    final response = await _apiClient.get('/api/v1/health');
    return response.statusCode >= 200 && response.statusCode < 300;
  }

  Future<http.Response> sendCommand(MirrorCommand command) {
    return _apiClient.postJson(
      '/api/v1/mirror/commands',
      body: {'deviceId': AppConfig.mirrorDeviceId, 'command': command.value},
    );
  }

  void close() => _apiClient.close();
}
