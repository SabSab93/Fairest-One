import 'dart:convert';

import 'package:fairest_one/core/network/api_client.dart';
import 'package:fairest_one/features/registration/data/client_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('creates a client through the production API', () async {
    final httpClient = MockClient((request) async {
      expect(request.url.toString(), 'https://example.test/api/clients');
      expect(request.method, 'POST');
      expect(jsonDecode(request.body), {
        'email': 'client@exemple.fr',
        'card_uid': 'DEMO-123',
      });
      return http.Response('{"created":true}', 201);
    });
    final store = RemoteClientStore(
      apiClient: ApiClient(
        client: httpClient,
        baseUrl: 'https://example.test/api/',
      ),
    );

    final result = await store.createClient(
      email: 'CLIENT@EXEMPLE.FR',
      cardUid: 'demo-123',
    );

    expect(result, ClientSaveResult.created);
  });

  test('sends the password when loading the admin client list', () async {
    final httpClient = MockClient((request) async {
      expect(request.headers['x-admin-password'], 'iou');
      return http.Response(
        jsonEncode([
          {
            'id': 'client-id',
            'email': 'client@exemple.fr',
            'card_uid': 'DEMO-123',
            'photo_count': 2,
            'created_at': '2026-09-30T10:00:00.000Z',
          },
        ]),
        200,
      );
    });
    final store = RemoteClientStore(
      apiClient: ApiClient(
        client: httpClient,
        baseUrl: 'https://example.test/api/',
      ),
    );

    final clients = await store.getClients(adminPassword: 'iou');

    expect(clients.single.email, 'client@exemple.fr');
    expect(clients.single.photoCount, 2);
  });

  test('reports an invalid admin password', () async {
    final store = RemoteClientStore(
      apiClient: ApiClient(
        client: MockClient((_) async => http.Response('{}', 401)),
        baseUrl: 'https://example.test/api/',
      ),
    );

    expect(
      () => store.getClients(adminPassword: 'incorrect'),
      throwsA(isA<AdminAccessDeniedException>()),
    );
  });

  test('finds a client from a card UID', () async {
    final httpClient = MockClient((request) async {
      expect(
        request.url.toString(),
        'https://example.test/api/clients?card_uid=DEMO-123',
      );
      return http.Response(
        jsonEncode({
          'id': 'client-id',
          'email': 'client@exemple.fr',
          'card_uid': 'DEMO-123',
          'photo_count': 0,
          'created_at': '2026-09-30T10:00:00.000Z',
        }),
        200,
      );
    });
    final store = RemoteClientStore(
      apiClient: ApiClient(
        client: httpClient,
        baseUrl: 'https://example.test/api/',
      ),
    );

    final client = await store.findByCardUid('demo-123');

    expect(client?.cardUid, 'DEMO-123');
  });
}
