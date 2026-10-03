import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/config/app_config.dart';
import '../../../core/network/api_client.dart';
import '../domain/client_record.dart';

enum ClientSaveResult { created, emailAlreadyExists, cardAlreadyAssigned }

class AdminAccessDeniedException implements Exception {
  const AdminAccessDeniedException();
}

abstract interface class ClientStore {
  Future<List<ClientRecord>> getClients({String? adminPassword});

  Future<ClientSaveResult> createClient({
    required String email,
    required String cardUid,
  });

  Future<ClientRecord?> findByCardUid(String cardUid);
}

class RemoteClientStore implements ClientStore {
  RemoteClientStore({ApiClient? apiClient})
    : _apiClient = apiClient ?? ApiClient(baseUrl: AppConfig.dataApiBaseUrl);

  final ApiClient _apiClient;

  @override
  Future<List<ClientRecord>> getClients({String? adminPassword}) async {
    final response = await _apiClient.get(
      'clients',
      headers: {'X-Admin-Password': ?adminPassword},
    );

    if (response.statusCode == 401) {
      throw const AdminAccessDeniedException();
    }
    if (response.statusCode != 200) {
      throw StateError('Client API returned ${response.statusCode}.');
    }

    final rows = jsonDecode(response.body) as List<dynamic>;
    return rows
        .map((row) => _recordFromApi(row as Map<String, dynamic>))
        .toList(growable: false);
  }

  @override
  Future<ClientSaveResult> createClient({
    required String email,
    required String cardUid,
  }) async {
    final response = await _apiClient.postJson(
      'clients',
      body: {
        'email': email.trim().toLowerCase(),
        'card_uid': cardUid.trim().toUpperCase(),
      },
    );

    if (response.statusCode == 201) return ClientSaveResult.created;
    if (response.statusCode == 409) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return body['code'] == 'email_already_exists'
          ? ClientSaveResult.emailAlreadyExists
          : ClientSaveResult.cardAlreadyAssigned;
    }
    throw StateError('Client API returned ${response.statusCode}.');
  }

  @override
  Future<ClientRecord?> findByCardUid(String cardUid) async {
    final encodedUid = Uri.encodeQueryComponent(cardUid.trim().toUpperCase());
    final response = await _apiClient.get('clients?card_uid=$encodedUid');
    if (response.statusCode == 404) return null;
    if (response.statusCode != 200) {
      throw StateError('Client API returned ${response.statusCode}.');
    }
    return _recordFromApi(jsonDecode(response.body) as Map<String, dynamic>);
  }

  ClientRecord _recordFromApi(Map<String, dynamic> row) {
    return ClientRecord(
      id: row['id'] as String,
      email: row['email'] as String,
      cardUid: row['card_uid'] as String?,
      photoCount: (row['photo_count'] as num?)?.toInt() ?? 0,
      createdAt: DateTime.parse(row['created_at'] as String),
    );
  }
}

class DemoCardStore {
  const DemoCardStore();

  static const _lastCardKey = 'fairest_one.last_demo_card_uid';

  Future<void> save(String cardUid) {
    return SharedPreferencesAsync().setString(
      _lastCardKey,
      cardUid.trim().toUpperCase(),
    );
  }

  Future<String?> read() {
    return SharedPreferencesAsync().getString(_lastCardKey);
  }
}

class ConfiguredClientStore implements ClientStore {
  const ConfiguredClientStore();

  static final ClientStore _store = RemoteClientStore();

  @override
  Future<ClientSaveResult> createClient({
    required String email,
    required String cardUid,
  }) => _store.createClient(email: email, cardUid: cardUid);

  @override
  Future<ClientRecord?> findByCardUid(String cardUid) =>
      _store.findByCardUid(cardUid);

  @override
  Future<List<ClientRecord>> getClients({String? adminPassword}) =>
      _store.getClients(adminPassword: adminPassword);
}
