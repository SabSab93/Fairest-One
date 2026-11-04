import React, { useCallback, useState, useSyncExternalStore } from 'react';
import { View } from 'react-native';
import { useFocusEffect } from 'expo-router';
import { Button, Copy, Heading, Page, s, Status } from '../components/ui';
import { cardReader, usesMirrorReader } from '../core/runtime';
import type { ClientRecord } from '../core/types';
export default function Photos() {
  const [client, setClient] = useState<ClientRecord>();
  const state = useSyncExternalStore(cardReader.subscribe, cardReader.getSnapshot, cardReader.getSnapshot);
  useFocusEffect(useCallback(() => () => { cardReader.stop('Lecture interrompue : vous avez quitté l’écran de lecture.'); setClient(undefined); }, []));
  const recover = async () => { setClient(undefined); try { const result = await cardReader.read('recovery'); setClient(result.client); } catch {} };
  return <Page><Heading>Vos{ '\n' }souvenirs.</Heading><Copy>{usesMirrorReader ? 'Retrouvez votre session en présentant votre carte au lecteur du miroir.' : 'Retrouvez votre session avec votre carte, sur le téléphone utilisé pour l’inscription.'}</Copy><Status flow={cardReader}/><Button disabled={state.busy} title={state.busy ? 'Lecture en cours…' : usesMirrorReader ? 'Lire ma carte sur le miroir' : 'Scanner ma carte'} onPress={() => { void recover(); }}/>{state.busy && <Button secondary title="Annuler" onPress={() => cardReader.stop()}/>}
    {client && <><View style={s.card}><Copy>{client.email}</Copy><Copy>{client.photo_count} capture(s) simulée(s)</Copy></View>{client.messages.length ? client.messages.map((message, i) => <View key={`${i}-${message}`} style={s.card}><Copy>{message}</Copy></View>) : <Copy>Aucune capture enregistrée pour cette session.</Copy>}</>}
  </Page>;
}
