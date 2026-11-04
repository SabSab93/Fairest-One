import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:nfc_manager/nfc_manager_android.dart';
import 'package:nfc_manager/nfc_manager_ios.dart';

abstract interface class PhoneNfcReader {
  Future<String> readUid();
  Future<void> cancel();
}

/// Keep the byte order identical to the RC522; no NDEF write is needed.
String nfcUidToHex(List<int> bytes) {
  if (![4, 7, 10].contains(bytes.length) ||
      bytes.any((b) => b < 0 || b > 255)) {
    throw StateError('Identifiant de carte NFC non pris en charge.');
  }
  return bytes
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join()
      .toUpperCase();
}

/// The NFC antenna position varies between Android models.
String get phoneNfcInstruction => defaultTargetPlatform == TargetPlatform.iOS
    ? 'Approchez la carte du haut de l’iPhone.'
    : 'Approchez la carte du dos du téléphone, près de son antenne NFC.';

class NativePhoneNfcReader implements PhoneNfcReader {
  NativePhoneNfcReader({
    NfcManager? manager,
    this.readTimeout = const Duration(seconds: 45),
  }) : _managerOverride = manager;
  final NfcManager? _managerOverride;
  final Duration readTimeout;
  NfcManager get _manager => _managerOverride ?? NfcManager.instance;
  Completer<String>? _pending;
  bool _started = false;

  @override
  Future<String> readUid() async {
    if (kIsWeb) {
      throw StateError(
        'La lecture NFC nécessite l’application Android ou iOS installée. Le site ne propose pas cette lecture.',
      );
    }
    if (defaultTargetPlatform != TargetPlatform.iOS &&
        defaultTargetPlatform != TargetPlatform.android) {
      throw StateError(
        'Utilisez l’application installée sur un téléphone Android ou iOS compatible NFC.',
      );
    }
    if (_pending != null) {
      throw StateError('Une lecture NFC est déjà en cours.');
    }
    final pending = Completer<String>();
    _pending = pending;
    // A native cancellation can arrive while startSession is still pending.
    pending.future.ignore();
    try {
      final availability = await _manager.checkAvailability().timeout(
        const Duration(seconds: 8),
      );
      if (pending.isCompleted) return await pending.future;
      if (availability == NfcAvailability.disabled) {
        throw StateError(
          'Activez le NFC dans les paramètres du téléphone, puis relancez la lecture.',
        );
      }
      if (availability != NfcAvailability.enabled) {
        throw StateError(
          'Ce téléphone ne dispose pas d’un lecteur NFC compatible.',
        );
      }
      _started = true;
      await _manager
          .startSession(
            pollingOptions: {NfcPollingOption.iso14443},
            alertMessageIos: phoneNfcInstruction,
            invalidateAfterFirstReadIos: false,
            onDiscovered: (tag) {
              if (pending.isCompleted) return;
              try {
                final bytes = defaultTargetPlatform == TargetPlatform.iOS
                    ? MiFareIos.from(tag)?.identifier
                    : NfcAAndroid.from(tag)?.tag.id;
                if (bytes == null) {
                  throw StateError(
                    'Utilisez une carte compatible, par exemple NTAG215.',
                  );
                }
                pending.complete(nfcUidToHex(bytes));
              } catch (error, stack) {
                pending.completeError(error, stack);
              }
            },
            onSessionErrorIos: (_) {
              if (!pending.isCompleted) {
                pending.completeError(
                  StateError(
                    'Lecture NFC annulée ou interrompue. Relancez la lecture.',
                  ),
                );
              }
            },
          )
          .timeout(const Duration(seconds: 10));
      // A cancel may have invalidated while native startup was still pending.
      // Ensure the finally block also closes a session that finished starting later.
      _started = true;
      return await pending.future.timeout(
        readTimeout,
        onTimeout: () => throw StateError(
          'Aucune carte détectée. Relancez la lecture et approchez la carte de l’antenne NFC.',
        ),
      );
    } on PlatformException {
      throw StateError(
        defaultTargetPlatform == TargetPlatform.iOS
            ? 'Impossible de démarrer le NFC. Vérifiez la configuration NFC et la signature iOS dans Xcode.'
            : 'Impossible de démarrer le NFC. Activez-le dans les paramètres du téléphone, puis réessayez.',
      );
    } finally {
      await _stopSession();
      if (identical(_pending, pending)) _pending = null;
    }
  }

  Future<void> _stopSession() async {
    if (!_started) return;
    _started = false;
    try {
      await _manager.stopSession().timeout(const Duration(seconds: 3));
    } catch (_) {
      // Session may already have been invalidated by iOS or the user.
    }
  }

  @override
  Future<void> cancel() async {
    final pending = _pending;
    if (pending != null && !pending.isCompleted) {
      pending.completeError(StateError('Lecture NFC annulée.'));
    }
    await _stopSession();
  }
}
