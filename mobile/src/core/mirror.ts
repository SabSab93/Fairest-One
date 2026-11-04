import { Flow } from './state';
import { ApiError } from './api';
import { cancellation, checkActive, delay, normalizeUid } from './async';
import type { Api, BleEvent, MirrorTransport, Purpose } from './types';

export class MirrorFlow extends Flow {
  constructor(private readonly api: Api, private readonly ble: MirrorTransport, private readonly eventTimeout = 35000) { super(); }
  private event(type: string, token: string, command: Record<string, unknown>, signal: AbortSignal) {
    return new Promise<BleEvent>((resolve, reject) => {
      let settled = false;
      let unsubscribe = () => {};
      const finish = (event?: BleEvent, error?: Error) => {
        if (settled) return;
        settled = true; clearTimeout(timer); unsubscribe(); signal.removeEventListener('abort', abort);
        if (error) reject(error); else resolve(event!);
      };
      const abort = () => finish(undefined, cancellation(signal));
      const timer = setTimeout(() => finish(undefined, new Error('Le miroir ne répond pas. Relancez la connexion.')), this.eventTimeout);
      unsubscribe = this.ble.subscribe(event => {
        if (event instanceof Error) return finish(undefined, event);
        if (event.token !== token) return;
        if (event.type === 'error') return finish(undefined, new Error('Le miroir a interrompu la lecture. Réessayez.'));
        if (event.type === type) finish(event);
      });
      signal.addEventListener('abort', abort, { once: true });
      if (signal.aborted) abort();
      else void this.ble.send(command, signal).catch(error => finish(undefined, error));
    });
  }
  read(purpose: Purpose, email?: string) {
    return this.run(async signal => {
      const normalizedEmail = email?.trim().toLowerCase();
      if (purpose === 'registration' && (!normalizedEmail || normalizedEmail.length > 254 || !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(normalizedEmail))) {
        throw new Error('Saisissez une adresse e-mail valide.');
      }
      let token: string | undefined;
      let completed = false;
      this.publish('Connexion Bluetooth au lecteur du miroir…', 'checking');
      try {
        await this.ble.connect(signal);
        checkActive(signal);
        const begin = await this.api.post({ action: `begin_${purpose}`, ...(purpose === 'registration' ? { email: normalizedEmail } : {}) }, signal);
        token = begin.token;
        if (!token || !/^[0-9a-f]{64}$/.test(token)) throw new Error('Demande du miroir invalide.');
        this.publish('Présentez votre carte au lecteur du miroir.', 'reading');
        const scan = await this.event('card_scanned', token, { type: 'scan', token }, signal);
        const uid = normalizeUid(scan.uid);
        if (!scan.proof || !/^[0-9a-f]{64}$/.test(scan.proof)) throw new Error('Lecture du miroir non signée.');
        this.publish(purpose === 'registration' ? 'Enregistrement de votre carte…' : 'Récupération de votre session…', 'checking');
        const result = await this.api.post({ action: 'scan', token, card_uid: uid, proof: scan.proof }, signal);
        checkActive(signal);
        if (result.state === 'failed' || result.state === 'unknown') {
          await this.ble.send({ type: 'card_result', token, recognized: false, capture: false }, signal);
          completed = true;
          if (result.state === 'unknown') throw new Error('Cette carte n’est pas enregistrée.');
          throw new Error(result.code === 'email_already_exists' ? 'Cette adresse e-mail est déjà enregistrée.' : 'Cette carte est déjà associée à un client.');
        }
        if (result.state !== (purpose === 'registration' ? 'associated' : 'recovered')) throw new Error('Lecture non confirmée. Réessayez.');
        if (purpose === 'recovery' && !result.client) throw new Error('La session reçue est incomplète.');
        // The backend has committed. Losing the LED/buzzer acknowledgment must
        // not report a failed registration or encourage creating another client.
        completed = true;
        try { await this.ble.send({ type: 'card_result', token, recognized: true, capture: false }, signal); }
        catch {
          checkActive(signal);
          this.publish(purpose === 'registration' ? 'Carte enregistrée ; connexion au miroir interrompue.' : 'Session récupérée ; connexion au miroir interrompue.', 'saved');
          return { ...result, uid };
        }
        this.publish(purpose === 'registration' ? 'Votre carte est enregistrée.' : 'Session récupérée', 'saved');
        return { ...result, uid };
      } finally {
        if (!completed && token) {
          void this.ble.send({ type: 'cancel', token }).catch(() => {});
          void this.api.post({ action: 'cancel', token }).catch(() => {});
        }
        await this.ble.disconnect();
      }
    });
  }
  private async capture(signal: AbortSignal) {
    let token: string | undefined;
    let completed = false;
    try {
      const begin = await this.api.post({ action: 'begin_recognition' }, signal);
      token = begin.token;
      if (!token || !/^[0-9a-f]{64}$/.test(token)) throw new Error('Demande du miroir invalide.');
      this.publish('Présentez la carte au RC522 du miroir.', 'reading');
      const scan = await this.event('card_scanned', token, { type: 'scan', token }, signal);
      const uid = normalizeUid(scan.uid);
      if (!scan.proof || !/^[0-9a-f]{64}$/.test(scan.proof)) throw new Error('Lecture du miroir non signée.');
      this.publish('Vérification de la carte…', 'checking');
      const result = await this.api.post({ action: 'scan', token, card_uid: uid, proof: scan.proof }, signal);
      checkActive(signal);
      if (result.state === 'unknown') {
        await this.ble.send({ type: 'card_result', token, recognized: false, capture: false }, signal);
        completed = true;
        this.publish('Carte inconnue · aucune capture enregistrée.', 'error');
        return;
      }
      if (result.state !== 'recognized') throw new Error('Le service n’a pas autorisé la capture.');
      this.publish('Carte reconnue · compte à rebours 3, 2, 1', 'countdown');
      const event = await this.event('capture_simulated', token, { type: 'card_result', token, recognized: true, capture: true }, signal);
      if (normalizeUid(event.uid) !== uid || !event.proof || !/^[0-9a-f]{64}$/.test(event.proof)) throw new Error('Confirmation de capture invalide.');
      const body = { action: 'capture', token, card_uid: uid, proof: event.proof };
      let saved;
      try { saved = await this.api.post(body, signal); }
      catch (error) {
        checkActive(signal);
        if (!(error instanceof ApiError) || (error.status > 0 && error.status < 500)) throw error;
        saved = await this.api.post(body, signal);
      }
      if (saved.state !== 'captured') throw new Error('Enregistrement de la capture non confirmé.');
      await this.ble.send({ type: 'capture_saved', token }, signal);
      completed = true;
      this.publish('Capture simulée enregistrée', 'saved');
    } finally {
      if (!completed && token) {
        void this.ble.send({ type: 'cancel', token }).catch(() => {});
        void this.api.post({ action: 'cancel', token }).catch(() => {});
      }
    }
  }
  start() {
    return this.run(async signal => {
      this.publish('Connexion Bluetooth au miroir…', 'checking');
      try {
        await this.ble.connect(signal);
        while (!signal.aborted) { await this.capture(signal); await delay(2000, signal); }
      } finally { await this.ble.disconnect(); }
    });
  }
}
