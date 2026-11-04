import React, { useCallback, useRef, useState } from 'react';
import { AppState, TextInput, View } from 'react-native';
import { useFocusEffect } from 'expo-router';
import { api } from '../core/runtime';
import { Button, Copy, Heading, Page, s } from '../components/ui';
import type { ClientRecord } from '../core/types';
import { errorMessage } from '../core/async';
export default function Admin() {
  const [password, setPassword] = useState('');
  const [clients, setClients] = useState<ClientRecord[] | null>(null);
  const [tab, setTab] = useState<'clients' | 'photos' | 'logs'>('clients');
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);
  const request = useRef<AbortController | null>(null);
  const clear = useCallback(() => { request.current?.abort(); setPassword(''); setClients(null); setBusy(false); }, []);
  useFocusEffect(useCallback(() => {
    const subscription = AppState.addEventListener('change', state => { if (state === 'background') clear(); });
    return () => { clear(); subscription.remove(); };
  }, [clear]));
  const unlock = async () => {
    const controller = new AbortController(); request.current = controller; setBusy(true); setError('');
    try { const rows = await api.clients(password, controller.signal); if (!controller.signal.aborted) { setClients(rows); setPassword(''); } }
    catch (e) { if (!controller.signal.aborted) setError(errorMessage(e)); }
    finally { if (!controller.signal.aborted) setBusy(false); }
  };
  return <Page><Heading>Administration.</Heading>{clients === null ? <><Copy>Accès réservé à l’équipe Fairest One.</Copy><TextInput accessibilityLabel="Mot de passe administrateur" secureTextEntry autoCapitalize="none" autoCorrect={false} value={password} onChangeText={setPassword} style={s.input} editable={!busy}/>{!!error && <Copy accessibilityRole="alert">{error}</Copy>}<Button title={busy ? 'Vérification…' : 'Se connecter'} disabled={busy || !password} onPress={() => { void unlock(); }}/></> : <><Copy>{clients.length} clients · {clients.reduce((sum, c) => sum + c.photo_count, 0)} captures</Copy><View style={{ gap: 8 }}><Button secondary title="Clients" onPress={() => setTab('clients')}/><Button secondary title="Photos" onPress={() => setTab('photos')}/><Button secondary title="Logs" onPress={() => setTab('logs')}/></View>{tab === 'logs' ? <Copy>Les journaux techniques sont disponibles dans Vercel et dans le moniteur USB du miroir.</Copy> : clients.map(client => <View style={s.card} key={client.id}><Copy>{client.email}</Copy>{tab === 'clients' && <><Copy>Carte : {client.card_uid ?? 'Non associée'}</Copy><Copy>{new Date(client.created_at).toLocaleDateString('fr-FR')}</Copy></>}<Copy>{client.photo_count} capture(s) simulée(s)</Copy></View>)}<Button title="Se déconnecter" onPress={clear}/></>}</Page>;
}
