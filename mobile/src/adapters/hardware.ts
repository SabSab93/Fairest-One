import Constants from 'expo-constants';
import * as Crypto from 'expo-crypto';
import * as SecureStore from 'expo-secure-store';
import { PermissionsAndroid, Platform } from 'react-native';
import type { BleManager, Device, Subscription } from 'react-native-ble-plx';
import { Cancelled, checkActive, wait } from '../core/async';
import { BleFrames, commandFrames, SERVICE as SERVICE_UUID, EVENTS as EVENTS_UUID, COMMANDS as COMMANDS_UUID } from '../core/ble-protocol';
import type { AccessStore, BleEvent, MirrorTransport, PhoneReader } from '../core/types';

function nativeBuild() {
  if (Constants.executionEnvironment === 'storeClient') throw new Error('Installez la version Fairest One construite avec EAS pour utiliser le NFC et le Bluetooth.');
}
const key = 'fairest_one.expo.phone_access.v1';
export const accessStore: AccessStore = {
  read: () => SecureStore.getItemAsync(key),
  save: value => SecureStore.setItemAsync(key, value, { keychainAccessible: SecureStore.WHEN_UNLOCKED_THIS_DEVICE_ONLY }),
  generate: async () => Array.from(await Crypto.getRandomBytesAsync(32), b => b.toString(16).padStart(2, '0')).join(''),
};
export const phoneReader: PhoneReader = {
  async readUid(signal) {
    nativeBuild(); checkActive(signal);
    const { default: nfc, NfcTech, NfcAdapter } = await import('react-native-nfc-manager');
    if (!await nfc.isSupported()) throw new Error('Ce téléphone ne possède pas de lecteur NFC compatible.');
    await nfc.start(); checkActive(signal);
    if (Platform.OS === 'android' && !await nfc.isEnabled()) throw new Error('Activez le NFC dans les réglages du téléphone.');
    const cancel = () => { void nfc.cancelTechnologyRequest({ throwOnError: false }).catch(() => {}); };
    signal.addEventListener('abort', cancel, { once: true });
    try {
      checkActive(signal);
      // Android reader mode delivers the tag inside this Activity rather than
      // launching an NFC intent (which can change screen or background the app).
      const options = Platform.OS === 'android'
        ? { isReaderModeEnabled: true, readerModeFlags: NfcAdapter.FLAG_READER_NFC_A | NfcAdapter.FLAG_READER_SKIP_NDEF_CHECK }
        : { alertMessage: 'Approchez votre carte Fairest One.' };
      await wait(nfc.requestTechnology(Platform.OS === 'ios' ? NfcTech.MifareIOS : NfcTech.NfcA, options), signal, 45000, 'Aucune carte détectée. Réessayez en la déplaçant au dos du téléphone.');
      const tag = await nfc.getTag({ readNdef: false });
      checkActive(signal);
      if (!tag?.id) throw new Error('Identifiant de carte indisponible.');
      return tag.id;
    } finally {
      signal.removeEventListener('abort', cancel);
      await nfc.cancelTechnologyRequest({ throwOnError: false }).catch(() => {});
    }
  },
};

export class NativeMirror implements MirrorTransport {
  private manager?: BleManager;
  private device?: Device;
  private subscriptions: Subscription[] = [];
  private listeners = new Set<(event: BleEvent | Error) => void>();
  private queue: Promise<void> = Promise.resolve();
  subscribe(listener: (event: BleEvent | Error) => void) { this.listeners.add(listener); return () => { this.listeners.delete(listener); }; }
  private emit(event: BleEvent | Error) { this.listeners.forEach(listener => listener(event)); }
  async connect(signal: AbortSignal) {
    nativeBuild(); checkActive(signal);
    if (Platform.OS === 'android') {
      const permissions = Number(Platform.Version) >= 31
        ? [PermissionsAndroid.PERMISSIONS.BLUETOOTH_SCAN, PermissionsAndroid.PERMISSIONS.BLUETOOTH_CONNECT]
        : [PermissionsAndroid.PERMISSIONS.ACCESS_FINE_LOCATION];
      const result = await PermissionsAndroid.requestMultiple(permissions);
      if (permissions.some(p => result[p] !== PermissionsAndroid.RESULTS.GRANTED)) throw new Error('Autorisez les appareils à proximité pour connecter le miroir.');
    }
    checkActive(signal);
    const { BleManager: Manager, State } = await import('react-native-ble-plx');
    const manager = this.manager = new Manager();
    const abort = () => { manager.stopDeviceScan(); void this.device?.cancelConnection().catch(() => {}); };
    signal.addEventListener('abort', abort, { once: true });
    try {
      await wait(new Promise<void>((resolve, reject) => {
        const subscription = manager.onStateChange(state => {
          if (state === State.PoweredOn) resolve();
          else if (state !== State.Unknown && state !== State.Resetting) reject(new Error('Activez le Bluetooth et autorisez Fairest One dans les réglages.'));
        }, true);
        this.subscriptions.push(subscription);
      }), signal, 10000, 'Bluetooth indisponible.');
      const found = await wait(new Promise<Device>((resolve, reject) => {
        manager.startDeviceScan([SERVICE_UUID], null, (error, device) => {
          if (error) reject(new Error('Recherche Bluetooth impossible. Vérifiez les autorisations.'));
          else if (device) resolve(device);
        });
      }), signal, 12000, 'Miroir introuvable. Allumez-le et vérifiez le firmware Fairest One.');
      manager.stopDeviceScan(); checkActive(signal);
      this.device = found;
      const connected = await wait(found.connect({ timeout: 12000 }), signal, 15000, 'La connexion au miroir a expiré.');
      this.device = connected;
      await connected.discoverAllServicesAndCharacteristics(); checkActive(signal);
      const frames = new BleFrames();
      this.subscriptions.push(connected.onDisconnected(() => this.emit(new Error('Connexion au miroir perdue. Rapprochez-vous puis reconnectez-le.'))));
      this.subscriptions.push(connected.monitorCharacteristicForService(SERVICE_UUID, EVENTS_UUID, (error, characteristic) => {
        if (signal.aborted) return;
        if (error) { this.emit(new Error('Lecture Bluetooth interrompue. Reconnectez le miroir.')); return; }
        if (!characteristic?.value) return;
        try { frames.add(characteristic.value).forEach(event => this.emit(event)); }
        catch { this.emit(new Error('Message Bluetooth invalide. Reconnectez le miroir.')); }
      }));
    } finally {
      manager.stopDeviceScan(); signal.removeEventListener('abort', abort);
    }
  }
  send(command: Record<string, unknown>, signal?: AbortSignal) {
    const task = this.queue.catch(() => {}).then(async () => {
      if (signal?.aborted) throw new Cancelled();
      const device = this.device;
      if (!device) throw new Error('Miroir déconnecté.');
      for (const value of commandFrames(command)) {
        if (signal?.aborted) throw new Cancelled();
        await device.writeCharacteristicWithResponseForService(SERVICE_UUID, COMMANDS_UUID, value);
      }
    });
    this.queue = task;
    return task;
  }
  async disconnect() {
    this.subscriptions.splice(0).forEach(s => s.remove());
    this.manager?.stopDeviceScan();
    await this.device?.cancelConnection().catch(() => {});
    this.device = undefined;
    await this.manager?.destroy().catch(() => {}); this.manager = undefined;
    this.queue = Promise.resolve();
  }
}
