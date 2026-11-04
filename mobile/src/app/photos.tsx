import React, { useCallback, useState, useSyncExternalStore } from 'react';
import { View } from 'react-native';
import { useFocusEffect } from 'expo-router';
import { Button, Copy, Heading, Page, s, Status } from '../components/ui';
import { phone } from '../core/runtime';
import type { ClientRecord } from '../core/types';
export default function Photos() {
  const [client, setClient] = useState<ClientRecord>();
  const state = useSyncExternalStore(phone.subscribe, phone.getSnapshot, phone.getSnapshot);
  useFocusEffect(useCallback(() => () => { phone.stop(); setClient(undefined); }, []));
  const recover = async () => { setClient(undefined); try { const result = await phone.read('recovery'); setClient(result.client); } catch {} };
  return <Page><Heading>Vos{ '\n' }souvenirs.</Heading><Copy>Retrouvez votre session avec votre carte, sur le téléphone utilisé pour l’inscription.</Copy><Status flow={phone}/><Button disabled={state.busy} title={state.busy ? 'Lecture en cours…' : 'Scanner ma carte'} onPress={() => { void recover(); }}/>{state.busy && <Button secondary title="Annuler" onPress={() => phone.stop()}/>}
    {client && <><View style={s.card}><Copy>{client.email}</Copy><Copy>{client.photo_count} capture(s) simulée(s)</Copy></View>{client.messages.length ? client.messages.map((message, i) => <View key={`${i}-${message}`} style={s.card}><Copy>{message}</Copy></View>) : <Copy>Aucune capture enregistrée pour cette session.</Copy>}</>}
  </Page>;
}
