import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';

import '../../../core/network/api_client.dart';
import 'ble_mirror_client.dart';
import '../domain/mirror_status.dart';

class NfcFlowController with WidgetsBindingObserver {
  NfcFlowController({
    required this.ble,
    required this.api,
    this.eventTimeout = const Duration(seconds: 35),
  });
  static final instance = NfcFlowController(
    ble: BleMirrorClient(),
    api: ApiClient(),
  );
  final MirrorBleTransport ble;
  final ApiClient api;
  final Duration eventTimeout;
  final status = ValueNotifier<String>('Miroir BLE déconnecté');
  final state = ValueNotifier<MirrorStatus>(MirrorStatus.offline);
  Completer<void>? _idle;
  Future<void> get whenIdle => _idle?.future ?? Future<void>.value();
  bool _stopping = false;
  bool _busy = false;
  int _generation = 0;
  bool _tryingOn = false;
  bool _observing = false;
  String? _token;
  Completer<Map<String, dynamic>>? _waiting;

  Future<Map<String, dynamic>> _post(Map<String, Object?> body) async {
    final response = await api.postJson('clients', body: body);
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode != 200) {
      throw StateError(data['error'] as String? ?? 'Backend indisponible.');
    }
    return data;
  }

  Future<Map<String, dynamic>> _wait(
    String type,
    String token,
    Future<void> Function() trigger,
  ) async {
    final completer = Completer<Map<String, dynamic>>();
    _waiting = completer;
    final subscription = ble.events.listen(
      (event) {
        if (event['token'] != token) return;
        if (event['type'] == 'error') {
          if (!completer.isCompleted) {
            completer.completeError(
              StateError(
                'Le miroir attendait une réponse. Relancez la lecture.',
              ),
            );
          }
        } else if (event['type'] == type && !completer.isCompleted) {
          completer.complete(event);
        }
      },
      onError: (Object error) {
        if (!completer.isCompleted) completer.completeError(error);
      },
    );
    final timer = Timer(eventTimeout, () {
      if (!completer.isCompleted) {
        completer.completeError(TimeoutException('Aucune réponse du miroir.'));
      }
    });
    try {
      final values = await Future.wait<Object?>([
        Future<void>.sync(trigger),
        completer.future,
      ], eagerError: true);
      return values[1] as Map<String, dynamic>;
    } finally {
      timer.cancel();
      await subscription.cancel();
      if (identical(_waiting, completer)) _waiting = null;
    }
  }

  Future<Map<String, dynamic>> read(String purpose, {String? email}) async {
    if (_busy && _stopping) await _idle!.future;
    if (_busy) throw StateError('Une lecture est déjà en cours.');
    _busy = true;
    _stopping = false;
    _idle = Completer<void>();
    if (!_observing) {
      WidgetsBinding.instance.addObserver(this);
      _observing = true;
    }
    final generation = _generation;
    void checkActive() {
      if (generation != _generation) throw StateError('Lecture annulée.');
    }

    String? token;
    try {
      status.value = 'Connexion Bluetooth…';
      await ble.connect();
      checkActive();
      state.value = MirrorStatus.ready;
      final challenge = await _post({
        'action': 'begin_$purpose',
        'email': ?email,
      });
      token = challenge['token'] as String;
      checkActive();
      _token = token;
      status.value = 'Présentez la carte au RC522';
      final scan = await _wait(
        'card_scanned',
        token,
        () => ble.send({'type': 'scan', 'token': token}),
      );
      checkActive();
      state.value = MirrorStatus.cardDetected;
      status.value = 'Vérification de la carte…';
      final result = await _post({
        'action': 'scan',
        'token': token,
        'card_uid': scan['uid'],
        'proof': scan['proof'],
      });
      checkActive();
      final recognized = result['state'] == 'recognized';
      if (recognized) {
        state.value = MirrorStatus.countdown;
        status.value = 'Carte reconnue · compte à rebours 3, 2, 1';
        final capture = await _wait(
          'capture_simulated',
          token,
          () => ble.send({
            'type': 'card_result',
            'token': token,
            'recognized': true,
            'capture': true,
          }),
        );
        checkActive();
        // Retrying the identical capture is safe: the backend persists it once.
        final body = {
          'action': 'capture',
          'token': token,
          'card_uid': capture['uid'],
          'proof': capture['proof'],
        };
        try {
          await _post(body);
        } catch (_) {
          await _post(body);
        }
        await ble.send({'type': 'capture_saved', 'token': token});
        state.value = MirrorStatus.photoUploaded;
        status.value = 'Capture simulée enregistrée';
      } else {
        await ble.send({
          'type': 'card_result',
          'token': token,
          'recognized': ['associated', 'recovered'].contains(result['state']),
          'capture': false,
        });
        state.value =
            result['state'] == 'unknown' || result['state'] == 'failed'
            ? MirrorStatus.error
            : MirrorStatus.ready;
        status.value = switch (result['state']) {
          'associated' => 'Client et carte NFC enregistrés dans Supabase.',
          'recovered' => 'Session récupérée',
          'unknown' => 'Carte inconnue · aucune capture',
          'failed' => switch (result['code']) {
            'email_already_exists' =>
              'Cette adresse email est déjà enregistrée.',
            'card_already_assigned' =>
              'Cette carte est déjà associée à un client.',
            _ => 'Association refusée. Relancez la lecture.',
          },
          _ => 'Lecture non confirmée. Relancez la lecture.',
        };
      }
      return {...result, 'uid': scan['uid']};
    } catch (error) {
      state.value = MirrorStatus.error;
      final message = error is StateError
          ? error.message
          : error is TimeoutException
          ? 'Délai dépassé. Relancez la lecture.'
          : 'Vérifiez le Bluetooth et Internet, puis relancez la lecture.';
      status.value = 'Lecture interrompue : $message';
      rethrow;
    } finally {
      if (token != null) {
        try {
          await ble.send({'type': 'cancel', 'token': token});
        } catch (_) {}
        try {
          await _post({'action': 'cancel', 'token': token});
        } catch (_) {}
      }
      _token = null;
      _busy = false;
      _idle?.complete();
    }
  }

  Future<void> startTryOn() async {
    if (_tryingOn || _busy) return;
    _tryingOn = true;
    final generation = _generation;
    try {
      while (_tryingOn && generation == _generation) {
        await read('recognition');
        // Preserve success/rejection feedback, then arm a new one-use challenge.
        await Future<void>.delayed(const Duration(seconds: 2));
      }
    } catch (_) {
      // status contains the actionable error; the user can reconnect explicitly.
    } finally {
      if (generation == _generation) _tryingOn = false;
    }
  }

  void stop() {
    _generation++;
    _stopping = true;
    _tryingOn = false;
    final waiting = _waiting;
    if (waiting != null && !waiting.isCompleted) {
      waiting.completeError(StateError('Lecture annulée.'));
    }
    final token = _token;
    if (token != null) {
      unawaited(
        ble.send({'type': 'cancel', 'token': token}).catchError((Object _) {}),
      );
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      stop();
      unawaited(ble.disconnect());
      this.state.value = MirrorStatus.offline;
      status.value = 'Bluetooth suspendu · relancez la lecture au retour';
    }
  }
}
