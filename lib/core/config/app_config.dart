class AppConfig {
  const AppConfig._();

  static const dataApiBaseUrl = String.fromEnvironment(
    'APP_API_URL',
    defaultValue: '/api/',
  );

  // Empty until the Raspberry Pi HTTP API is available.
  static const mirrorApiBaseUrl = String.fromEnvironment('MIRROR_API_URL');

  static bool get useMockIot => mirrorApiBaseUrl.isEmpty;
  static const requestTimeout = Duration(seconds: 10);
}
