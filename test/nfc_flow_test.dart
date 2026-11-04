import 'dart:async';
import 'dart:convert';

import 'package:fairest_one/core/network/api_client.dart';
import 'package:fairest_one/features/mirror/data/ble_mirror_client.dart';
import 'package:fairest_one/features/mirror/data/nfc_flow_controller.dart';
import 'package:flutter/material.dart';
import 'package:fairest_one/features/registration/presentation/registration_screen.dart';
import 'package:fairest_one/features/photo_recovery/presentation/photo_recovery_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class FakeBle implements MirrorBleTransport {
  final source = StreamController<Map<String, dynamic>>.broadcast();
  final sent = <Map<String, Object?>>[];
  bool respond = true;
  bool disconnected = false;
  @override
  Stream<Map<String, dynamic>> get events => source.stream;
  @override
  Future<void> connect() async {}
  @override
  Future<void> disconnect() async {
    disconnected = true;
  }

  @override
  Future<void> send(Map<String, Object?> command) async {
    sent.add(command);
    if (!respond) return;
    final type = command['type'];
    if (type == 'scan' ||
        (type == 'card_result' && command['capture'] == true)) {
      source.add({
        'type': type == 'scan' ? 'card_scanned' : 'capture_simulated',
        'token': 'wrong-token',
        'uid': 'FFFFFFFF',
        'proof': 'bad',
      });
      source.add({
        'type': type == 'scan' ? 'card_scanned' : 'capture_simulated',
        'token': command['token'],
        'uid': 'A1B2C3D4',
        'proof': 'test-proof',
      });
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('JSON lines tolerate fragmented UTF-8 and multiple frames', () {
    final decoder = BleJsonDecoder();
    final bytes = utf8.encode(
      '${jsonEncode({'type': 'capture_simulated', 'label': 'Essayage effectué.'})}\n',
    );
    final messages = <Map<String, dynamic>>[];
    for (final byte in bytes) {
      messages.addAll(decoder.add([byte]));
    }
    expect(messages.single['label'], 'Essayage effectué.');
    expect(decoder.add(utf8.encode('bad json\n{}\n')).length, 1);
    expect(() => decoder.add(List.filled(1025, 65)), throwsFormatException);
  });
  for (final recovery in [false, true]) {
    testWidgets(
      recovery
          ? 'recovery screen renders three backend messages'
          : 'existing registration form confirms BLE association',
      (tester) async {
        final ble = FakeBle();
        final api = ApiClient(
          baseUrl: 'https://example.test/api/',
          client: MockClient((request) async {
            final body = jsonDecode(request.body);
            if ((body['action'] as String).startsWith('begin_')) {
              return http.Response(jsonEncode({'token': 'a' * 64}), 200);
            }
            return http.Response(
              jsonEncode(
                recovery
                    ? {
                        'state': 'recovered',
                        'client': {
                          'id': 'test-client',
                          'email': 'a@example.test',
                          'card_uid': 'A1B2C3D4',
                          'created_at': '2026-11-04T10:00:00Z',
                          'photo_count': 3,
                          'messages': List.generate(
                            3,
                            (i) =>
                                'Photo simulée n°${i + 1} — Essayage effectué.',
                          ),
                        },
                      }
                    : {'state': 'associated'},
              ),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }),
        );
        final flow = NfcFlowController(ble: ble, api: api);
        await tester.binding.setSurfaceSize(const Size(390, 844));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          MaterialApp(
            home: recovery
                ? PhotoRecoveryScreen(
                    nfcController: flow,
                    useMockIot: false,
                    usePhoneNfc: false,
                  )
                : RegistrationScreen(
                    nfcController: flow,
                    useMockIot: false,
                    usePhoneNfc: false,
                  ),
          ),
        );
        if (!recovery) {
          await tester.enterText(
            find.byKey(const Key('client-email-field')),
            'a@example.test',
          );
          await tester.ensureVisible(find.text('CRÉER LA SESSION'));
        }
        // StreamSubscription.cancel can return a future from the real zone.
        // Let the external BLE/HTTP flow finish outside the fake frame clock.
        await tester.runAsync(() async {
          await tester.tap(
            find.text(recovery ? 'LIRE LA CARTE' : 'CRÉER LA SESSION'),
          );
          await flow.whenIdle;
        });
        await tester.pumpAndSettle();
        if (recovery) {
          expect(
            find.text('Photo simulée n°3 — Essayage effectué.'),
            findsOneWidget,
          );
          expect(find.text('a@example.test'), findsOneWidget);
        } else {
          expect(find.text('SESSION CRÉÉE'), findsOneWidget);
          expect(
            find.text('Client et carte NFC enregistrés dans Supabase.'),
            findsOneWidget,
          );
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        WidgetsBinding.instance.removeObserver(flow);
        api.close();
        await ble.source.close();
      },
    );
  }
  for (final state in ['associated', 'recognized', 'unknown', 'recovered']) {
    test('BLE scan routes $state through the existing HTTP service', () async {
      final ble = FakeBle();
      final actions = <String>[];
      var captureAttempts = 0;
      final api = ApiClient(
        baseUrl: 'https://example.test/api/',
        client: MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          final action = body['action'] as String;
          actions.add(action);
          if (action.startsWith('begin_')) {
            return http.Response(jsonEncode({'token': 'a' * 64}), 200);
          }
          if (action == 'scan') {
            expect(body['card_uid'], 'A1B2C3D4');
            return http.Response(jsonEncode({'state': state}), 200);
          }
          if (action == 'capture' && captureAttempts++ == 0) {
            return http.Response('{"error":"network"}', 502);
          }
          return http.Response('{"state":"captured"}', 200);
        }),
      );
      final flow = NfcFlowController(ble: ble, api: api);
      try {
        final result = await flow.read(
          state == 'associated'
              ? 'registration'
              : state == 'recovered'
              ? 'recovery'
              : 'recognition',
          email: 'a@example.test',
        );
        expect(result['state'], state);
        final confirmation = ble.sent.firstWhere(
          (c) => c['type'] == 'card_result',
        );
        expect(confirmation['recognized'], state != 'unknown');
        expect(confirmation['capture'], state == 'recognized');
        expect(
          actions.where((a) => a == 'capture').length,
          state == 'recognized' ? 2 : 0,
        );
      } finally {
        WidgetsBinding.instance.removeObserver(flow);
        api.close();
        await ble.source.close();
      }
    });
  }
  test('backend failure does not authorize a capture', () async {
    final ble = FakeBle();
    final api = ApiClient(
      baseUrl: 'https://example.test/api/',
      client: MockClient((request) async {
        final body = jsonDecode(request.body);
        if ((body['action'] as String).startsWith('begin_')) {
          return http.Response(jsonEncode({'token': 'a' * 64}), 200);
        }
        return http.Response('{"error":"Backend indisponible"}', 502);
      }),
    );
    final flow = NfcFlowController(ble: ble, api: api);
    await expectLater(flow.read('recognition'), throwsStateError);
    expect(ble.sent.any((c) => c['type'] == 'card_result'), isFalse);
    expect(ble.sent.last['type'], 'cancel');
    WidgetsBinding.instance.removeObserver(flow);
    api.close();
    await ble.source.close();
  });
  for (final failure in ['timeout', 'disconnect', 'cancel']) {
    test('$failure interrupts a pending read without capture', () async {
      final ble = FakeBle()..respond = false;
      final api = ApiClient(
        baseUrl: 'https://example.test/api/',
        client: MockClient(
          (_) async => http.Response(jsonEncode({'token': 'a' * 64}), 200),
        ),
      );
      final flow = NfcFlowController(
        ble: ble,
        api: api,
        eventTimeout: const Duration(milliseconds: 30),
      );
      final operation = flow.read('recognition');
      final expectation = expectLater(operation, throwsA(anything));
      await Future<void>.delayed(const Duration(milliseconds: 5));
      if (failure == 'disconnect') {
        ble.source.addError(StateError('BLE déconnecté'));
      }
      if (failure == 'cancel') flow.stop();
      await expectation;
      expect(ble.sent.any((c) => c['type'] == 'card_result'), isFalse);
      WidgetsBinding.instance.removeObserver(flow);
      api.close();
      await ble.source.close();
    });
  }
}
