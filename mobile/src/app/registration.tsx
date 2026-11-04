import React, { useCallback, useState, useSyncExternalStore } from 'react';
import { Keyboard, TextInput, View } from 'react-native';
import { router, useFocusEffect } from 'expo-router';
import { Button, Copy, Heading, Page, s, Status } from '../components/ui';
import { cardReader, usesMirrorReader } from '../core/runtime';
export default function Registration() {
  const [email, setEmail] = useState('');
  const [saved, setSaved] = useState(false);
  const state = useSyncExternalStore(cardReader.subscribe, cardReader.getSnapshot, cardReader.getSnapshot);
  useFocusEffect(useCallback(() => () => cardReader.stop('Lecture interrompue : vous avez quitté l’écran de lecture.'), []));
  const register = async () => { Keyboard.dismiss(); try { await cardReader.read('registration', email); setSaved(true); } catch {} };
  return <Page><Heading>Nouveau{ '\n' }client.</Heading><Copy>Associez votre carte à votre e-mail. Elle vous accompagnera pendant vos essayages.</Copy>
    {saved ? <View style={s.card}><Copy>Votre carte est enregistrée. Vous pouvez maintenant l’utiliser sur le miroir.</Copy><Button title="Continuer" onPress={() => router.replace('/')}/></View> : <><Copy>E-mail</Copy><TextInput accessibilityLabel="Adresse e-mail" autoComplete="email" keyboardType="email-address" autoCapitalize="none" autoCorrect={false} editable={!state.busy} value={email} onChangeText={setEmail} placeholder="vous@exemple.fr" style={s.input}/><Copy>{usesMirrorReader ? 'Allumez le miroir, appuyez sur le bouton puis présentez la carte au lecteur du miroir.' : 'Appuyez sur le bouton, puis approchez la carte du dos du téléphone.'}</Copy><Status flow={cardReader}/><Button title={state.busy ? 'Lecture en cours…' : usesMirrorReader ? 'Associer ma carte avec le miroir' : 'Lire ma carte NFC'} disabled={state.busy || !email.trim()} onPress={() => { void register(); }}/>{state.busy && <Button secondary title="Annuler" onPress={() => cardReader.stop()}/>}</>}
  </Page>;
}
