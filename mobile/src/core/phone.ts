import { Flow } from './state';
import { checkActive, normalizeUid } from './async';
import { ApiError } from './api';
import type { AccessStore, Api, PhoneReader, Purpose } from './types';

export class PhoneFlow extends Flow {
  constructor(private readonly api: Api, private readonly reader: PhoneReader, private readonly access: AccessStore) { super(); }
  async read(purpose: Purpose, email?: string) {
    return this.run(async signal => {
      const normalizedEmail = email?.trim().toLowerCase();
      if (purpose === 'registration' && (!normalizedEmail || !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(normalizedEmail))) {
        throw new Error('Saisissez une adresse e-mail valide.');
      }
      let challenge: string | undefined;
      let mobile: string | null = null;
      let completed = false;
      try {
        this.publish('Approchez la carte de l’antenne NFC du téléphone.', 'reading');
        const uid = normalizeUid(await this.reader.readUid(signal));
        checkActive(signal);
        mobile = await this.access.read();
        checkActive(signal);
        if (!mobile) {
          if (purpose === 'recovery') throw new Error('Utilisez le téléphone et l’application ayant inscrit cette carte.');
          mobile = await this.access.generate();
          if (!/^[0-9a-f]{64}$/.test(mobile)) throw new Error('Impossible de préparer un accès sécurisé.');
          await this.access.save(mobile);
          if (await this.access.read() !== mobile) throw new Error('Impossible de conserver l’accès sécurisé. Aucune inscription envoyée.');
        }
        checkActive(signal);
        this.publish(purpose === 'registration' ? 'Enregistrement de votre carte…' : 'Récupération de votre session…', 'checking');
        const begin = await this.api.post({ action: `begin_phone_${purpose}`, mobile_token: mobile, ...(normalizedEmail ? { email: normalizedEmail } : {}) }, signal);
        challenge = begin.token;
        if (!challenge || !/^[0-9a-f]{64}$/.test(challenge)) throw new Error('Demande de lecture invalide.');
        checkActive(signal);
        const body = { action: 'phone_scan', token: challenge, mobile_token: mobile, card_uid: uid };
        let result;
        try { result = await this.api.post(body, signal); }
        catch (error) {
          if (purpose !== 'registration' || !(error instanceof ApiError) || (error.status > 0 && error.status < 500)) throw error;
          checkActive(signal);
          result = await this.api.post(body, signal);
        }
        checkActive(signal);
        if (result.state === 'failed') {
          completed = true;
          throw new Error(result.code === 'email_already_exists' ? 'Cette adresse e-mail est déjà enregistrée.' : 'Cette carte est déjà associée à un client.');
        }
        if (result.state !== (purpose === 'registration' ? 'associated' : 'recovered')) throw new Error('Lecture non confirmée. Réessayez.');
        if (purpose === 'recovery' && !result.client) throw new Error('La session reçue est incomplète.');
        completed = true;
        this.publish(purpose === 'registration' ? 'Votre carte est enregistrée.' : 'Session récupérée', 'saved');
        return { ...result, uid };
      } finally {
        if (!completed && challenge && mobile) {
          void this.api.post({ action: 'phone_cancel', token: challenge, mobile_token: mobile }).catch(() => {});
        }
      }
    });
  }
}
