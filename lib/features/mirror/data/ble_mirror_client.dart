import 'dart:async';
import 'dart:convert';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

const fairestServiceUuid = '83de1000-7a28-4b54-9815-47c0ae451001';
const fairestEventsUuid = '83de1001-7a28-4b54-9815-47c0ae451001';
const fairestCommandsUuid = '83de1002-7a28-4b54-9815-47c0ae451001';

/// JSON lines, fragmented into 20-byte ATT payloads (also works at MTU 23).
class BleJsonDecoder {
  final List<int> _bytes = [];
  List<Map<String, dynamic>> add(List<int> chunk) {
    final messages = <Map<String, dynamic>>[];
    for (final byte in chunk) {
      if (byte == 10) {
        try {
          final value = jsonDecode(utf8.decode(_bytes));
          if (value is Map<String, dynamic>) messages.add(value);
        } on FormatException {
          // Discard invalid frames; the operation's timeout remains active.
        }
        _bytes.clear();
      } else {
        _bytes.add(byte);
        if (_bytes.length > 1024) {
          _bytes.clear();
          throw const FormatException('Message BLE trop long.');
        }
      }
    }
    return messages;
  }
}

abstract interface class MirrorBleTransport {
  Stream<Map<String, dynamic>> get events;
  Future<void> connect();
  Future<void> send(Map<String, Object?> command);
  Future<void> disconnect();
}

class BleMirrorClient implements MirrorBleTransport {
  final _events = StreamController<Map<String, dynamic>>.broadcast();
  Future<void> _writes = Future<void>.value();
  BluetoothDevice? _device;
  BluetoothCharacteristic? _commands;
  StreamSubscription<List<int>>? _notifications;
  StreamSubscription<BluetoothConnectionState>? _connection;
  @override
  Stream<Map<String, dynamic>> get events => _events.stream;

  @override
  Future<void> connect() async {
    if (_device?.isConnected == true && _commands != null) return;
    await disconnect();
    final adapter = await FlutterBluePlus.adapterState
        .where((s) => s != BluetoothAdapterState.unknown)
        .first
        .timeout(const Duration(seconds: 8));
    if (adapter != BluetoothAdapterState.on) {
      throw StateError(
        'Activez le Bluetooth et autorisez Fairest One dans Réglages.',
      );
    }
    final found = Completer<BluetoothDevice>();
    final scan = FlutterBluePlus.onScanResults.listen(
      (results) {
        if (results.isNotEmpty && !found.isCompleted) {
          found.complete(results.first.device);
        }
      },
      onError: (Object error) {
        if (!found.isCompleted) found.completeError(error);
      },
    );
    try {
      await FlutterBluePlus.startScan(
        withServices: [Guid(fairestServiceUuid)],
        timeout: const Duration(seconds: 10),
      );
      _device = await found.future.timeout(const Duration(seconds: 12));
    } finally {
      await FlutterBluePlus.stopScan();
      await scan.cancel();
    }
    try {
      await _device!.connect(
        license: License.nonprofit,
        timeout: const Duration(seconds: 15),
      );
      final services = await _device!.discoverServices();
      final service = services.firstWhere(
        (s) => s.uuid == Guid(fairestServiceUuid),
      );
      final notify = service.characteristics.firstWhere(
        (c) => c.uuid == Guid(fairestEventsUuid),
      );
      _commands = service.characteristics.firstWhere(
        (c) => c.uuid == Guid(fairestCommandsUuid),
      );
      final decoder = BleJsonDecoder();
      _notifications = notify.onValueReceived.listen((bytes) {
        try {
          for (final event in decoder.add(bytes)) {
            _events.add(event);
          }
        } catch (error) {
          _events.addError(error);
        }
      }, onError: _events.addError);
      _connection = _device!.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected) {
          _commands = null;
          _events.addError(
            StateError('Bluetooth déconnecté. Relancez la lecture.'),
          );
        }
      });
      await notify.setNotifyValue(true);
    } catch (_) {
      await disconnect();
      rethrow;
    }
  }

  @override
  Future<void> send(Map<String, Object?> command) {
    final operation = _writes.then((_) => _send(command));
    _writes = operation.catchError((Object _) {});
    return operation;
  }

  Future<void> _send(Map<String, Object?> command) async {
    final characteristic = _commands;
    if (characteristic == null) throw StateError('Miroir déconnecté.');
    final bytes = utf8.encode('${jsonEncode(command)}\n');
    for (var offset = 0; offset < bytes.length; offset += 20) {
      await characteristic.write(
        bytes.sublist(offset, (offset + 20).clamp(0, bytes.length)),
        withoutResponse: false,
      );
    }
  }

  @override
  Future<void> disconnect() async {
    await _connection?.cancel();
    await _notifications?.cancel();
    _connection = null;
    _notifications = null;
    _commands = null;
    final device = _device;
    _device = null;
    if (device?.isConnected == true) await device!.disconnect();
  }
}
