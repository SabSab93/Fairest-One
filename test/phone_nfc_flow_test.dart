import 'dart:async';
import 'dart:convert';

import 'package:fairest_one/core/network/api_client.dart';
import 'package:fairest_one/features/nfc/data/phone_access_store.dart';
import 'package:fairest_one/features/nfc/data/phone_nfc_flow_controller.dart';
import 'package:fairest_one/features/nfc/data/phone_nfc_reader.dart';
import 'package:fairest_one/features/photo_recovery/presentation/photo_recovery_screen.dart';
import 'package:fairest_one/features/registration/presentation/registration_screen.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:nfc_manager/nfc_manager_ios.dart';
// The pinned plugin's native payload types back its public NfcTag test constructor.
// ignore: implementation_imports
import 'package:nfc_manager/src/nfc_manager_android/pigeon.g.dart'
    as android_codec;
// ignore: implementation_imports
import 'package:nfc_manager/src/nfc_manager_ios/pigeon.g.dart' as ios_codec;

class FakePhoneReader implements PhoneNfcReader {
  int reads = 0;
  int cancels = 0;
  Completer<String>? pending;
  @override
  Future<String> readUid() async {
    reads++;
    return pending == null ? '04010203040506' : await pending!.future;
  }

  @override
  Future<void> cancel() async {
    cancels++;
    if (pending != null && !pending!.isCompleted) {
      pending!.completeError(StateError('Lecture NFC annulée.'));
    }
  }
}

class MemoryPhoneAccess implements PhoneAccessStore {
  String? token;
  bool canSave = true;
  @override
  Future<String?> read() async => token;
  @override
  Future<void> save(String value) async {
    if (canSave) token = value;
  }
}

class FakeNfcManager implements NfcManager {
  NfcAvailability availability = NfcAvailability.enabled;
  void Function()? afterStart;
  void Function(NfcTag)? discovered;
  void Function(NfcReaderSessionErrorIos)? onError;
  Completer<void>? startup;
  int starts = 0;
  int stops = 0;
  @override
  Future<NfcAvailability> checkAvailability() async => availability;
  @override
  Future<bool> isAvailable() async => availability == NfcAvailability.enabled;
  @override
  Future<void> startSession({
    required Set<NfcPollingOption> pollingOptions,
    required void Function(NfcTag) onDiscovered,
    String? alertMessageIos,
    bool invalidateAfterFirstReadIos = true,
    void Function(NfcReaderSessionErrorIos)? onSessionErrorIos,
    bool noPlatformSoundsAndroid = false,
  }) async {
    expect(pollingOptions, {NfcPollingOption.iso14443});
    expect(invalidateAfterFirstReadIos, isFalse);
    starts++;
    onError = onSessionErrorIos;
    discovered = onDiscovered;
    afterStart?.call();
    await startup?.future;
  }

  @override
  Future<void> stopSession({
    String? alertMessageIos,
    String? errorMessageIos,
  }) async {
    stops++;
  }
}

http.Response jsonResponse(Object data, int status) => http.Response(
  jsonEncode(data),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
Map<String, Object?> recovered() => {
  'state': 'recovered',
  'client': {
    'id': 'phone-client',
    'email': 'phone@example.test',
    'card_uid': '04010203040506',
    'photo_count': 3,
    'created_at': '2026-11-04T10:00:00Z',
    'messages': List.generate(
      3,
      (i) => 'Photo simulée n°${i + 1} — Essayage effectué.',
    ),
  },
};
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('UID bytes retain RC522 byte order and leading zeroes', () {
    expect(nfcUidToHex([4, 1, 2, 3, 4, 5, 6]), '04010203040506');
    expect(nfcUidToHex([0, 10, 0, 255]), '000A00FF');
    expect(() => nfcUidToHex([4, 1, 2]), throwsStateError);
    expect(() => nfcUidToHex([256, 0, 0, 0]), throwsStateError);
    expect(newPhoneAccessToken(), matches(RegExp(r'^[a-f0-9]{64}$')));
  });
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    test(
      '${platform.name} decodes a native NTAG payload once in RC522 byte order',
      () async {
        debugDefaultTargetPlatformOverride = platform;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        final bytes = Uint8List.fromList([4, 1, 2, 3, 4, 5, 6]);
        final payload = platform == TargetPlatform.android
            ? android_codec.TagPigeon(
                handle: 'test-tag',
                id: bytes,
                techList: ['android.nfc.tech.NfcA'],
                nfcA: android_codec.NfcAPigeon(
                  atqa: Uint8List.fromList([0x44, 0]),
                  sak: 0,
                ),
              )
            : ios_codec.TagPigeon(
                handle: 'test-tag',
                miFare: ios_codec.MiFarePigeon(
                  mifareFamily: ios_codec.MiFareFamilyPigeon.ultralight,
                  identifier: bytes,
                ),
              );
        final manager = FakeNfcManager();
        manager.afterStart = () {
          manager.discovered!(NfcTag(data: payload));
          manager.discovered!(NfcTag(data: payload));
        };
        final reader = NativePhoneNfcReader(manager: manager);
        expect(await reader.readUid(), '04010203040506');
        expect(manager.stops, 1);
      },
    );
  }
  test('Android rejects a tag that the RC522 cannot read as NFC-A', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final manager = FakeNfcManager();
    manager.afterStart = () => manager.discovered!(
      NfcTag(
        data: android_codec.TagPigeon(
          handle: 'wrong-tech',
          id: Uint8List.fromList([1, 2, 3, 4]),
          techList: ['android.nfc.tech.NfcV'],
        ),
      ),
    );
    await expectLater(
      NativePhoneNfcReader(manager: manager).readUid(),
      throwsStateError,
    );
    expect(manager.stops, 1);
  });
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    for (final purpose in ['registration', 'recovery']) {
      testWidgets(
        '${platform.name} $purpose screen uses phone NFC without BLE',
        (tester) async {
          final reader = FakePhoneReader();
          final access = MemoryPhoneAccess()..token = 'b' * 64;
          final actions = <String>[];
          final api = ApiClient(
            baseUrl: 'https://example.test/api/',
            client: MockClient((request) async {
              final body = jsonDecode(request.body) as Map<String, dynamic>;
              actions.add(body['action'] as String);
              expect(body['mobile_token'], access.token);
              expect(body.containsKey('proof'), isFalse);
              if ((body['action'] as String).startsWith('begin_')) {
                return jsonResponse({'token': 'a' * 64}, 200);
              }
              expect(body['card_uid'], '04010203040506');
              return jsonResponse(
                purpose == 'registration'
                    ? {'state': 'associated'}
                    : recovered(),
                200,
              );
            }),
          );
          final flow = PhoneNfcFlowController(
            reader: reader,
            accessStore: access,
            api: api,
          );
          await tester.binding.setSurfaceSize(const Size(390, 844));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          await tester.pumpWidget(
            MaterialApp(
              home: purpose == 'registration'
                  ? RegistrationScreen(
                      useMockIot: false,
                      phoneNfcController: flow,
                    )
                  : PhotoRecoveryScreen(
                      useMockIot: false,
                      phoneNfcController: flow,
                    ),
            ),
          );
          if (purpose == 'registration') {
            await tester.enterText(
              find.byKey(const Key('client-email-field')),
              'phone@example.test',
            );
            await tester.ensureVisible(find.text('CRÉER LA SESSION'));
          }
          await tester.runAsync(() async {
            await tester.tap(
              find.text(
                purpose == 'registration'
                    ? 'CRÉER LA SESSION'
                    : 'LIRE LA CARTE',
              ),
            );
            await flow.whenIdle;
          });
          await tester.pumpAndSettle();
          expect(reader.reads, 1);
          expect(actions, ['begin_phone_$purpose', 'phone_scan']);
          if (purpose == 'registration') {
            expect(find.text('SESSION CRÉÉE'), findsOneWidget);
          } else {
            expect(
              find.text('Photo simulée n°3 — Essayage effectué.'),
              findsOneWidget,
            );
            expect(find.text('phone@example.test'), findsOneWidget);
          }
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
          api.close();
        },
      );
    }
  }
  test(
    'personal credential is saved before registration and reused on retry',
    () async {
      final access = MemoryPhoneAccess();
      var scans = 0;
      final api = ApiClient(
        baseUrl: 'https://example.test/api/',
        client: MockClient((request) async {
          final body = jsonDecode(request.body);
          expect(access.token, isNotNull);
          expect(body['mobile_token'], access.token);
          if (body['action'] == 'begin_phone_registration') {
            return jsonResponse({'token': 'a' * 64}, 200);
          }
          if (scans++ == 0) throw http.ClientException('lost acknowledgement');
          return jsonResponse({'state': 'associated'}, 200);
        }),
      );
      final flow = PhoneNfcFlowController(
        reader: FakePhoneReader(),
        accessStore: access,
        api: api,
      );
      expect(
        (await flow.read('registration', email: 'phone@example.test'))['state'],
        'associated',
      );
      expect(access.token, matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(scans, 2);
      api.close();
    },
  );
  for (final failure in [
    'missing access',
    'Keychain failure',
    'insecure HTTP',
  ]) {
    test('$failure cannot disclose or send customer data', () async {
      var calls = 0;
      final access = MemoryPhoneAccess()..canSave = false;
      final reader = FakePhoneReader();
      final api = ApiClient(
        baseUrl: failure == 'insecure HTTP'
            ? 'http://example.test/api/'
            : 'https://example.test/api/',
        client: MockClient((_) async {
          calls++;
          return jsonResponse({}, 200);
        }),
      );
      final flow = PhoneNfcFlowController(
        reader: reader,
        accessStore: access,
        api: api,
      );
      await expectLater(
        flow.read(
          failure == 'missing access' ? 'recovery' : 'registration',
          email: 'phone@example.test',
        ),
        throwsStateError,
      );
      expect(calls, 0);
      api.close();
    });
  }
  test(
    'forbidden recovery displays backend error and never returns a client',
    () async {
      final access = MemoryPhoneAccess()..token = 'b' * 64;
      final api = ApiClient(
        baseUrl: 'https://example.test/api/',
        client: MockClient((request) async {
          final body = jsonDecode(request.body);
          return body['action'] == 'begin_phone_recovery'
              ? jsonResponse({'token': 'a' * 64}, 200)
              : jsonResponse({
                  'error': 'Accès refusé. Utilisez l’iPhone de l’inscription.',
                }, 403);
        }),
      );
      final flow = PhoneNfcFlowController(
        reader: FakePhoneReader(),
        accessStore: access,
        api: api,
      );
      await expectLater(flow.read('recovery'), throwsStateError);
      expect(flow.status.value, contains('Accès refusé'));
      api.close();
    },
  );
  test(
    'Core NFC inactive sheet is allowed; background cancels without HTTP',
    () async {
      var calls = 0;
      final reader = FakePhoneReader()..pending = Completer<String>();
      final api = ApiClient(
        baseUrl: 'https://example.test/api/',
        client: MockClient((_) async {
          calls++;
          return jsonResponse({}, 200);
        }),
      );
      final flow = PhoneNfcFlowController(
        reader: reader,
        accessStore: MemoryPhoneAccess(),
        api: api,
      );
      final operation = flow.read('registration', email: 'phone@example.test');
      final expectation = expectLater(operation, throwsStateError);
      flow.didChangeAppLifecycleState(AppLifecycleState.inactive);
      expect(reader.cancels, 0);
      flow.didChangeAppLifecycleState(AppLifecycleState.paused);
      await expectation;
      expect(calls, 0);
      expect(reader.cancels, 1);
      api.close();
    },
  );
  test(
    'cancellation during native startup closes a late-started session',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final manager = FakeNfcManager()..startup = Completer<void>();
      final reader = NativePhoneNfcReader(manager: manager);
      final operation = reader.readUid();
      final expectation = expectLater(operation, throwsStateError);
      await Future<void>.delayed(const Duration(milliseconds: 1));
      expect(manager.starts, 1);
      await reader.cancel();
      manager.startup!.complete();
      await expectation;
      expect(manager.stops, 2);
    },
  );
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    for (final scenario in ['unavailable', 'disabled', 'timeout', 'cancel']) {
      test(
        '${platform.name} session handles $scenario and releases the reader',
        () async {
          debugDefaultTargetPlatformOverride = platform;
          addTearDown(() => debugDefaultTargetPlatformOverride = null);
          final manager = FakeNfcManager();
          if (scenario == 'disabled') {
            manager.availability = NfcAvailability.disabled;
          }
          if (scenario == 'unavailable') {
            manager.availability = NfcAvailability.unsupported;
          }
          final reader = NativePhoneNfcReader(
            manager: manager,
            readTimeout: const Duration(milliseconds: 10),
          );
          final operation = reader.readUid();
          final expectedMessage = switch (scenario) {
            'unavailable' => 'ne dispose pas',
            'disabled' => 'Activez le NFC',
            'timeout' => 'Aucune carte détectée',
            _ => 'Lecture NFC annulée',
          };
          final expectation = expectLater(
            operation,
            throwsA(
              isA<StateError>().having(
                (error) => error.message,
                'message',
                contains(expectedMessage),
              ),
            ),
          );
          if (scenario == 'cancel') {
            await Future<void>.delayed(const Duration(milliseconds: 1));
            await reader.cancel();
          }
          await expectation;
          expect(
            manager.starts,
            ['unavailable', 'disabled'].contains(scenario) ? 0 : 1,
          );
          expect(
            manager.stops,
            ['unavailable', 'disabled'].contains(scenario) ? 0 : 1,
          );
        },
      );
    }
  }
}
