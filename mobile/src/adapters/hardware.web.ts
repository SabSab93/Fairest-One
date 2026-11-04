import type { AccessStore, MirrorTransport, PhoneReader } from '../core/types';
const unsupported = async (): Promise<never> => { throw new Error('Installez Fairest One sur Android ou iPhone via EAS pour utiliser le NFC et le Bluetooth.'); };
export const phoneReader: PhoneReader = { readUid: unsupported };
export const accessStore: AccessStore = { read: unsupported, save: unsupported, generate: unsupported };
export class NativeMirror implements MirrorTransport {
  connect = unsupported;
  send = unsupported;
  subscribe() { return () => {}; }
  async disconnect() {}
}
