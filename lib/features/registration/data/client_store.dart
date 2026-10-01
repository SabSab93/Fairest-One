import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

class LocalClientStore implements ClientStore {
  const LocalClientStore();

  static const _clientsKey = 'fairest_one.clients';
  static const _legacyEmailsKey = 'fairest_one.client_emails';

  @override
  Future<List<ClientRecord>> getClients({String? adminPassword}) async {
    final preferences = SharedPreferencesAsync();
    final encodedClients =
        await preferences.getStringList(_clientsKey) ?? <String>[];
    final clients = <ClientRecord>[];

    for (final encodedClient in encodedClients) {
      try {
        final json = jsonDecode(encodedClient) as Map<String, Object?>;
        clients.add(ClientRecord.fromJson(json));
      } on FormatException {
        continue;
      }
    }

    final legacyEmails =
        await preferences.getStringList(_legacyEmailsKey) ?? <String>[];
    for (final email in legacyEmails) {
      if (clients.any((client) => client.email == email)) continue;
      clients.add(
        ClientRecord(
          id: 'legacy-${email.hashCode}',
          email: email,
          cardUid: null,
          photoCount: 0,
          createdAt: DateTime.fromMillisecondsSinceEpoch(0),
        ),
      );
    }

    clients.sort((a, b) => a.email.compareTo(b.email));
    return List.unmodifiable(clients);
  }

  @override
  Future<ClientSaveResult> createClient({
    required String email,
    required String cardUid,
  }) async {
    final normalizedEmail = email.trim().toLowerCase();
    final normalizedCardUid = cardUid.trim().toUpperCase();
    final clients = (await getClients()).toList();

    if (clients.any((client) => client.email == normalizedEmail)) {
      return ClientSaveResult.emailAlreadyExists;
    }
    if (clients.any((client) => client.cardUid == normalizedCardUid)) {
      return ClientSaveResult.cardAlreadyAssigned;
    }

    clients.add(
      ClientRecord(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        email: normalizedEmail,
        cardUid: normalizedCardUid,
        photoCount: 0,
        createdAt: DateTime.now().toUtc(),
      ),
    );

    final preferences = SharedPreferencesAsync();
    await preferences.setStringList(
      _clientsKey,
      clients.map((client) => jsonEncode(client.toJson())).toList(),
    );
    return ClientSaveResult.created;
  }

  @override
  Future<ClientRecord?> findByCardUid(String cardUid) async {
    final normalizedCardUid = cardUid.trim().toUpperCase();
    for (final client in await getClients()) {
      if (client.cardUid == normalizedCardUid) return client;
    }
    return null;
  }
}

class SupabaseClientStore implements ClientStore {
  SupabaseClientStore(this._client);

  final SupabaseClient _client;

  @override
  Future<List<ClientRecord>> getClients({String? adminPassword}) async {
    final rows = await _client
        .from('clients')
        .select('id,email,card_uid,created_at,sessions(photos(id))')
        .order('email');

    return rows.map(_recordFromRow).toList(growable: false);
  }

  @override
  Future<ClientSaveResult> createClient({
    required String email,
    required String cardUid,
  }) async {
    try {
      await _client.from('clients').insert({
        'email': email.trim().toLowerCase(),
        'card_uid': cardUid.trim().toUpperCase(),
      });
      return ClientSaveResult.created;
    } on PostgrestException catch (error) {
      if (error.code == '23505' && error.message.contains('email')) {
        return ClientSaveResult.emailAlreadyExists;
      }
      if (error.code == '23505' && error.message.contains('card_uid')) {
        return ClientSaveResult.cardAlreadyAssigned;
      }
      rethrow;
    }
  }

  @override
  Future<ClientRecord?> findByCardUid(String cardUid) async {
    final row = await _client
        .from('clients')
        .select('id,email,card_uid,created_at,sessions(photos(id))')
        .eq('card_uid', cardUid.trim().toUpperCase())
        .maybeSingle();
    return row == null ? null : _recordFromRow(row);
  }

  ClientRecord _recordFromRow(Map<String, dynamic> row) {
    final sessions = row['sessions'] as List<dynamic>? ?? const [];
    var photoCount = 0;
    for (final session in sessions) {
      final sessionData = session as Map<String, dynamic>;
      photoCount +=
          (sessionData['photos'] as List<dynamic>? ?? const []).length;
    }

    return ClientRecord(
      id: row['id'] as String,
      email: row['email'] as String,
      cardUid: row['card_uid'] as String?,
      photoCount: photoCount,
      createdAt: DateTime.parse(row['created_at'] as String),
    );
  }
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

  static final ClientStore _remoteStore = RemoteClientStore();

  ClientStore get _delegate {
    if (AppConfig.useRemoteData) return _remoteStore;
    if (AppConfig.useSupabase) {
      return SupabaseClientStore(Supabase.instance.client);
    }
    return const LocalClientStore();
  }

  @override
  Future<ClientSaveResult> createClient({
    required String email,
    required String cardUid,
  }) {
    return _delegate.createClient(email: email, cardUid: cardUid);
  }

  @override
  Future<ClientRecord?> findByCardUid(String cardUid) {
    return _delegate.findByCardUid(cardUid);
  }

  @override
  Future<List<ClientRecord>> getClients({String? adminPassword}) {
    return _delegate.getClients(adminPassword: adminPassword);
  }
}
