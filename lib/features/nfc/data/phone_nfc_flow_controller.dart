import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';

import '../../../core/network/api_client.dart';
import 'phone_access_store.dart';
import 'phone_nfc_reader.dart';

class PhoneNfcFlowController with WidgetsBindingObserver {
  PhoneNfcFlowController({
    required this.reader,
    required this.accessStore,
    required this.api,
  });
  static final instance = PhoneNfcFlowController(
    reader: NativePhoneNfcReader(),
    accessStore: const SecurePhoneAccessStore(),
    api: ApiClient(),
  );
  final PhoneNfcReader reader;
  final PhoneAccessStore accessStore;
  final ApiClient api;
  final status = ValueNotifier<String>('Lecteur NFC du téléphone prêt');
  bool _busy = false;
  bool _stopping = false;
  int _generation = 0;
  Completer<void>? _idle;
  Future<void> get whenIdle => _idle?.future ?? Future<void>.value();

  Future<Map<String, dynamic>> _post(Map<String, Object?> body) async {
    final response = await api.postJson('clients', body: body);
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode != 200) {
      throw StateError(
        data['error'] as String? ?? 'Service indisponible. Réessayez.',
      );
    }
    return data;
  }

  Future<Map<String, dynamic>> read(String purpose, {String? email}) async {
    if (!['registration', 'recovery'].contains(purpose)) {
      throw ArgumentError.value(purpose);
    }
    if (_busy && _stopping) await whenIdle;
    if (_busy) throw StateError('Une lecture est déjà en cours.');
    _busy = true;
    _stopping = false;
    _idle = Completer<void>();
    final generation = _generation;
    void checkActive() {
      if (generation != _generation) throw StateError('Lecture annulée.');
    }

    bool completed = false;
    String? challenge;
    String? access;
    WidgetsBinding.instance.addObserver(this);
    try {
      if (!api.usesHttps) {
        throw StateError(
          'Configurez l’adresse HTTPS de l’API pour utiliser le NFC sur le téléphone.',
        );
      }
      status.value = phoneNfcInstruction;
      final uid = await reader.readUid();
      checkActive();
      access = await accessStore.read();
      checkActive();
      if (access == null) {
        if (purpose == 'recovery') {
          throw StateError(
            'Cette carte doit avoir été inscrite depuis ce téléphone pour y récupérer ses photos.',
          );
        }
        access = newPhoneAccessToken();
        // Persist before any backend write so a lost response does not lose access.
        await accessStore.save(access);
        if (await accessStore.read() != access) {
          throw StateError(
            'Impossible de conserver l’accès dans le stockage sécurisé. Aucune inscription envoyée.',
          );
        }
        checkActive();
      }
      status.value = purpose == 'registration'
          ? 'Enregistrement de la carte…'
          : 'Récupération de votre session…';
      final begin = await _post({
        'action': 'begin_phone_$purpose',
        'mobile_token': access,
        'email': ?email,
      });
      challenge = begin['token'] as String;
      checkActive();
      final body = {
        'action': 'phone_scan',
        'token': challenge,
        'mobile_token': access,
        'card_uid': uid,
      };
      Map<String, dynamic> result;
      if (purpose == 'registration') {
        // A registration acknowledgement is safely repeatable; recovery is one-use.
        try {
          result = await _post(body);
        } catch (_) {
          checkActive();
          result = await _post(body);
        }
      } else {
        result = await _post(body);
      }
      checkActive();
      status.value = switch (result['state']) {
        'associated' => 'Client et carte NFC enregistrés dans Supabase.',
        'recovered' => 'Session récupérée',
        'failed' => switch (result['code']) {
          'email_already_exists' => 'Cette adresse email est déjà enregistrée.',
          'card_already_assigned' =>
            'Cette carte est déjà associée à un client.',
          _ => 'Association refusée. Réessayez.',
        },
        _ => throw StateError('La lecture n’a pas été confirmée. Réessayez.'),
      };
      completed = true;
      return {...result, 'uid': uid};
    } catch (error) {
      final message = error is StateError
          ? error.message
          : error is TimeoutException
          ? 'Délai dépassé. Vérifiez Internet et relancez la lecture.'
          : 'Impossible de terminer la lecture. Vérifiez Internet et réessayez.';
      status.value = message.toString();
      rethrow;
    } finally {
      if (!completed && challenge != null && access != null) {
        try {
          await _post({
            'action': 'phone_cancel',
            'token': challenge,
            'mobile_token': access,
          });
        } catch (_) {}
      }
      WidgetsBinding.instance.removeObserver(this);
      _busy = false;
      _idle?.complete();
    }
  }

  void stop() {
    _stopping = true;
    _generation++;
    unawaited(reader.cancel().catchError((Object _) {}));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Core NFC's system sheet can make the app inactive: keep that session alive.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      stop();
    }
  }
}
