import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract interface class PhoneAccessStore {
  Future<String?> read();
  Future<void> save(String token);
}

String newPhoneAccessToken() {
  final random = Random.secure();
  return List.generate(
    32,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}

/// Personal runtime credential, never a Supabase/admin/mirror server key.
class KeychainPhoneAccessStore implements PhoneAccessStore {
  const KeychainPhoneAccessStore();
  static const _key = 'fairest_one.phone_access.v1';
  static const _storage = FlutterSecureStorage(
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.unlocked_this_device,
      synchronizable: false,
    ),
  );
  @override
  Future<String?> read() => _storage.read(key: _key);
  @override
  Future<void> save(String token) => _storage.write(key: _key, value: token);
}
