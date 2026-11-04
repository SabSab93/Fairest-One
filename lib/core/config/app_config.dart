class AppConfig {
  const AppConfig._();

  static const dataApiBaseUrl = String.fromEnvironment(
    'APP_API_URL',
    defaultValue: '/api/',
  );

  // Legacy gateway remains available for existing command integrations.
  static const mirrorApiBaseUrl = String.fromEnvironment('MIRROR_API_URL');

  static const useMockIot = bool.fromEnvironment(
    'USE_MOCK_IOT',
    defaultValue: false,
  );
  static const usePhoneNfc = bool.fromEnvironment(
    'USE_PHONE_NFC',
    defaultValue: true,
  );
  static const requestTimeout = Duration(seconds: 10);
}
