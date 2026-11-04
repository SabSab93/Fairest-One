import React, { useCallback, useSyncExternalStore } from 'react';
import { Text, View } from 'react-native';
import { router, useFocusEffect } from 'expo-router';
import { Button, colors, Copy, Heading, Page, s, Status } from '../components/ui';
import { mirror } from '../core/runtime';
export default function Home() {
  const state = useSyncExternalStore(mirror.subscribe, mirror.getSnapshot, mirror.getSnapshot);
  useFocusEffect(useCallback(() => () => mirror.stop(), []));
  return <Page back={false}><Heading>Votre expérience{ '\n' }d’essayage.</Heading><Copy>Une carte personnelle pour garder une trace de vos essayages.</Copy>
    <View style={[s.card, { backgroundColor: colors.ink }]}><Text style={[s.heading, { color: colors.paper, fontSize: 36, lineHeight: 40 }]}>Nouvelle session</Text><Copy style={{ color: colors.paper }}>Inscrivez votre e-mail, puis présentez votre carte au dos du téléphone.</Copy><Button secondary title="Nouveau client" onPress={() => router.push('/registration')}/></View>
    <View style={[s.card, { backgroundColor: colors.paleSage }]}><Text style={[s.heading, { fontSize: 36, lineHeight: 40 }]}>Retrouver mes photos</Text><Copy>Scannez votre carte avec ce même téléphone pour retrouver votre session.</Copy><Button title="Récupérer ma session" onPress={() => router.push('/photos')}/></View>
    <View style={s.card}><Copy style={{ fontWeight: '600' }}>Le miroir</Copy><Copy>Pour un essayage, connectez le miroir puis présentez votre carte au lecteur RC522. Gardez cet écran ouvert.</Copy><Status flow={mirror}/><Button title={state.busy ? 'Déconnecter le miroir' : 'Connecter le miroir'} onPress={() => { if (state.busy) mirror.stop(); else void mirror.start().catch(() => {}); }}/><Copy style={{ fontSize: 13 }}>Version de test : les captures sont simulées.</Copy></View>
    <Button secondary title="Administration" onPress={() => router.push('/admin')}/>
  </Page>;
}
