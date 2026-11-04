import { Buffer } from 'buffer';
import type { BleEvent } from './types';
export const SERVICE = '83de1000-7a28-4b54-9815-47c0ae451001';
export const EVENTS = '83de1001-7a28-4b54-9815-47c0ae451001';
export const COMMANDS = '83de1002-7a28-4b54-9815-47c0ae451001';

export class BleFrames {
  private bytes: number[] = [];
  add(base64: string): BleEvent[] {
    const events: BleEvent[] = [];
    for (const byte of Buffer.from(base64, 'base64')) {
      if (byte === 10) {
        try {
          const event: unknown = JSON.parse(Buffer.from(this.bytes).toString('utf8'));
          if (event && typeof event === 'object' && 'type' in event && 'token' in event
              && typeof event.type === 'string' && typeof event.token === 'string') events.push(event as BleEvent);
        } catch { /* Ignore invalid frames; operation timeout remains active. */ }
        this.bytes = [];
      } else {
        this.bytes.push(byte);
        if (this.bytes.length > 1024) { this.bytes = []; throw new Error('Message Bluetooth trop long.'); }
      }
    }
    return events;
  }
}
export function commandFrames(command: Record<string, unknown>): string[] {
  const bytes = Buffer.from(`${JSON.stringify(command)}\n`, 'utf8');
  const chunks: string[] = [];
  for (let offset = 0; offset < bytes.length; offset += 20) chunks.push(Buffer.from(bytes.subarray(offset, offset + 20)).toString('base64'));
  return chunks;
}
