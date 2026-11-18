import React, { useCallback, useSyncExternalStore } from 'react';
import { View } from 'react-native';
import { Redirect, router, useFocusEffect } from 'expo-router';
import { Button, Copy, Heading, Page, s, Status } from '../components/ui';
import { mirror, usesMirrorReader } from '../core/runtime';

export default function TryOn() {
  const state = useSyncExternalStore(mirror.subscribe, mirror.getSnapshot, mirror.getSnapshot);
  useFocusEffect(useCallback(() => () => mirror.stop('Essayage interrompu : vous avez quitté l’écran.'), []));
  if (!usesMirrorReader) return <Redirect href="/"/>;

  return <Page>
    <Heading>Votre{ '\n' }essayage.</Heading>
    <Copy>Votre carte doit d’abord être associée à votre e-mail.</Copy>
    <View style={s.card}>
      <Copy>1. Mettez vos lunettes et allumez le miroir.</Copy>
      <Copy>2. Appuyez sur « Lancer un essayage », puis présentez votre carte au lecteur du miroir quand l’application vous le demande.</Copy>
      <Copy>3. Après reconnaissance, attendez les deux bips, le compte à rebours et la confirmation d’enregistrement.</Copy>
    </View>
    <Status flow={mirror}/>
    <Button title={state.busy ? 'Essayage en cours…' : 'Lancer un essayage'} disabled={state.busy} onPress={() => { void mirror.tryOn().catch(() => {}); }}/>
    {state.busy && <Button secondary title="Annuler l’essayage" onPress={() => mirror.stop()}/>}
    <Copy>Pour essayer une autre monture, retirez la carte au moins une seconde, changez de lunettes et lancez un nouvel essayage. Gardez cet écran ouvert et Internet actif.</Copy>
    <Button secondary title="Récupérer ma session" disabled={state.busy} onPress={() => router.replace('/photos')}/>
    <Copy style={{ fontSize: 13 }}>Version de test : un message remplace chaque photo. L’envoi par e-mail sera ajouté ensuite.</Copy>
  </Page>;
}
