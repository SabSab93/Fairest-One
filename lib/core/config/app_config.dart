import 'package:flutter_dotenv/flutter_dotenv.dart';

class AppConfig {
  const AppConfig._();

  static String get apiBaseUrl {
    const buildValue = String.fromEnvironment('API_BASE_URL');
    return buildValue.isNotEmpty
        ? buildValue
        : _env('API_BASE_URL', 'http://raspberrypi.local:8080/');
  }

  static String get webSocketUrl {
    const buildValue = String.fromEnvironment('WS_BASE_URL');
    return buildValue.isNotEmpty
        ? buildValue
        : _env('WS_BASE_URL', 'ws://raspberrypi.local:8080/ws');
  }

  static String get mirrorDeviceId {
    const buildValue = String.fromEnvironment('MIRROR_DEVICE_ID');
    return buildValue.isNotEmpty
        ? buildValue
        : _env('MIRROR_DEVICE_ID', 'fairest-one-mirror-01');
  }

  static bool get useMockIot {
    const buildValue = String.fromEnvironment('USE_MOCK_IOT');
    final value = buildValue.isNotEmpty
        ? buildValue
        : _env('USE_MOCK_IOT', 'true');
    return value.toLowerCase() == 'true' || value == '1';
  }

  static Duration get requestTimeout {
    const buildValue = String.fromEnvironment('REQUEST_TIMEOUT_SECONDS');
    final value = buildValue.isNotEmpty
        ? buildValue
        : _env('REQUEST_TIMEOUT_SECONDS', '10');
    return Duration(seconds: int.tryParse(value) ?? 10);
  }

  static String get adminPinHash {
    const buildValue = String.fromEnvironment('ADMIN_PIN_HASH');
    return buildValue.isNotEmpty
        ? buildValue
        : _env(
            'ADMIN_PIN_HASH',
            '03ac674216f3e15c761ee1a5e255f067953623c8b388b4459e13f978d7c846f4',
          );
  }

  static String get supabaseUrl {
    const buildValue = String.fromEnvironment('SUPABASE_URL');
    return buildValue.isNotEmpty ? buildValue : _env('SUPABASE_URL', '');
  }

  static String get supabasePublishableKey {
    const buildValue = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
    return buildValue.isNotEmpty
        ? buildValue
        : _env('SUPABASE_PUBLISHABLE_KEY', '');
  }

  static bool get useSupabase {
    const buildValue = String.fromEnvironment('USE_SUPABASE');
    final value = buildValue.isNotEmpty
        ? buildValue
        : _env('USE_SUPABASE', 'false');
    return value.toLowerCase() == 'true' || value == '1';
  }

  static String _env(String key, String fallback) {
    if (!dotenv.isInitialized) return fallback;
    return dotenv.get(key, fallback: fallback);
  }
}
