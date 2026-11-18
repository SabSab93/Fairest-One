import React, { useCallback, useRef, useState } from 'react';
import { AppState, TextInput, View } from 'react-native';
import { useFocusEffect } from 'expo-router';
import { Button, colors, Copy, Heading, Page, s } from '../components/ui';
import { ApiError } from '../core/api';
import { errorMessage } from '../core/async';
import { api } from '../core/runtime';
import type { ClientRecord } from '../core/types';

export default function Admin() {
  const [password, setPassword] = useState('');
  const [clients, setClients] = useState<ClientRecord[] | null>(null);
  const [tab, setTab] = useState<'clients' | 'photos' | 'logs'>('clients');
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [error, setError] = useState('');
  const [notice, setNotice] = useState('');
  const [busy, setBusy] = useState(false);
  const request = useRef<AbortController | null>(null);
  const adminPassword = useRef('');

  const clear = useCallback(() => {
    request.current?.abort();
    request.current = null;
    adminPassword.current = '';
    setPassword('');
    setClients(null);
    setSelectedId(null);
    setError('');
    setNotice('');
    setBusy(false);
    setTab('clients');
  }, []);

  useFocusEffect(useCallback(() => {
    const subscription = AppState.addEventListener('change', state => { if (state === 'background') clear(); });
    return () => { clear(); subscription.remove(); };
  }, [clear]));

  const run = async (operation: (signal: AbortSignal) => Promise<void>) => {
    if (request.current) return;
    const controller = new AbortController();
    request.current = controller;
    setBusy(true);
    setError('');
    setNotice('');
    try {
      await operation(controller.signal);
    } catch (error) {
      if (!controller.signal.aborted) setError(errorMessage(error));
    } finally {
      if (request.current === controller) {
        request.current = null;
        setBusy(false);
      }
    }
  };

  const unlock = () => run(async signal => {
    const rows = await api.clients(password, signal);
    if (signal.aborted) return;
    adminPassword.current = password;
    setClients(rows);
    setPassword('');
  });

  const reset = (client: ClientRecord) => run(async signal => {
    if (!client.card_uid || !adminPassword.current || selectedId !== client.id) return;
    const credential = adminPassword.current;
    try {
      await api.resetCard(client.id, client.card_uid, credential, signal);
    } catch (error) {
      if (!signal.aborted && error instanceof ApiError && error.status === 404) {
        const rows = await api.clients(credential, signal);
        if (!signal.aborted) {
          setClients(rows);
          setSelectedId(null);
        }
      }
      throw error;
    }
    if (signal.aborted) return;
    setClients(rows => rows?.filter(row => row.id !== client.id) ?? null);
    setSelectedId(null);
    setNotice('Carte libérée. Elle peut être associée à un nouveau client.');
  });

  const changeTab = (next: typeof tab) => {
    setTab(next);
    setSelectedId(null);
    setError('');
  };

  return <Page>
    <Heading>Administration.</Heading>
    {clients === null ? <>
      <Copy>Accès réservé à l’équipe Fairest One.</Copy>
      <TextInput accessibilityLabel="Mot de passe administrateur" secureTextEntry autoCapitalize="none"
        autoCorrect={false} value={password} onChangeText={setPassword} style={s.input} editable={!busy}/>
      {!!error && <Copy accessibilityRole="alert">{error}</Copy>}
      <Button title={busy ? 'Vérification…' : 'Se connecter'} disabled={busy || !password} onPress={() => { void unlock(); }}/>
    </> : <>
      <Copy>{clients.length} clients · {clients.reduce((sum, client) => sum + client.photo_count, 0)} captures</Copy>
      <View style={{ gap: 8 }}>
        <Button secondary title="Clients" disabled={busy} onPress={() => changeTab('clients')}/>
        <Button secondary title="Photos" disabled={busy} onPress={() => changeTab('photos')}/>
        <Button secondary title="Logs" disabled={busy} onPress={() => changeTab('logs')}/>
      </View>
      {!!notice && <Copy accessibilityRole="alert">{notice}</Copy>}
      {!!error && !selectedId && <Copy accessibilityRole="alert">{error}</Copy>}
      {tab === 'logs' ? <Copy>Les journaux techniques sont disponibles dans Vercel et dans le moniteur USB du miroir.</Copy> :
        clients.map(client => <View style={s.card} key={client.id}>
          <Copy>{client.email}</Copy>
          {tab === 'clients' && <>
            <Copy>Carte : {client.card_uid ?? 'Non associée'}</Copy>
            <Copy>{new Date(client.created_at).toLocaleDateString('fr-FR')}</Copy>
          </>}
          <Copy>{client.photo_count} capture(s) simulée(s)</Copy>
          {tab === 'clients' && !!client.card_uid && (selectedId === client.id ?
            <View style={[s.card, { backgroundColor: colors.dustyRose }]}>
              <Copy accessibilityRole="header" style={{ fontWeight: '600' }}>Réinitialiser la carte</Copy>
              <Copy>Cette action supprime définitivement {client.email}, ses sessions et toutes ses captures. La carte pourra être attribuée à un autre client.</Copy>
              {!!error && <Copy accessibilityRole="alert">{error}</Copy>}
              <Button title={busy ? 'Réinitialisation…' : 'Supprimer et libérer la carte'} disabled={busy}
                onPress={() => { void reset(client); }}/>
              <Button secondary title="Annuler" disabled={busy} onPress={() => { setSelectedId(null); setError(''); }}/>
            </View> :
            <Button secondary title="Réinitialiser la carte" disabled={busy} onPress={() => {
              setSelectedId(client.id);
              setError('');
              setNotice('');
            }}/>)}
        </View>)
      }
      <Button title="Se déconnecter" onPress={clear}/>
    </>}
  </Page>;
}
