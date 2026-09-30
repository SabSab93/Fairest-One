import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/app_config.dart';
import '../domain/client_record.dart';

enum ClientSaveResult { created, emailAlreadyExists, cardAlreadyAssigned }

abstract interface class ClientStore {
  Future<List<ClientRecord>> getClients();

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
  Future<List<ClientRecord>> getClients() async {
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
  Future<List<ClientRecord>> getClients() async {
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

class ConfiguredClientStore implements ClientStore {
  const ConfiguredClientStore();

  ClientStore get _delegate => AppConfig.useSupabase
      ? SupabaseClientStore(Supabase.instance.client)
      : const LocalClientStore();

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
  Future<List<ClientRecord>> getClients() => _delegate.getClients();
}
