import React, { useCallback, useState, useSyncExternalStore } from 'react';
import { Text, TextInput, View } from 'react-native';
import { router, useFocusEffect } from 'expo-router';
import { Button, colors, Copy, Heading, Page, s, Status } from '../components/ui';
import { getWifiAddress, mirror, setWifiAddress, usesMirrorReader } from '../core/runtime';
export default function Home() {
  const [address, setAddress] = useState(getWifiAddress);
  const [addressMessage, setAddressMessage] = useState('');
  const state = useSyncExternalStore(mirror.subscribe, mirror.getSnapshot, mirror.getSnapshot);
  useFocusEffect(useCallback(() => () => mirror.stop(), []));
  return <Page back={false}><Heading>Votre expérience{ '\n' }d’essayage.</Heading><Copy>Une carte personnelle pour garder une trace de vos essayages.</Copy>
    <View style={[s.card, { backgroundColor: colors.ink }]}><Text style={[s.heading, { color: colors.paper, fontSize: 36, lineHeight: 40 }]}>Nouvelle session</Text><Copy style={{ color: colors.paper }}>{usesMirrorReader ? 'Inscrivez votre e-mail, puis présentez votre carte au lecteur du miroir.' : 'Inscrivez votre e-mail, puis présentez votre carte au dos du téléphone.'}</Copy><Button secondary title="Nouveau client" onPress={() => router.push('/registration')}/></View>
    <View style={[s.card, { backgroundColor: colors.paleSage }]}><Text style={[s.heading, { fontSize: 36, lineHeight: 40 }]}>Retrouver mes photos</Text><Copy>{usesMirrorReader ? 'Présentez votre carte au miroir pour retrouver votre session.' : 'Scannez votre carte avec ce même téléphone pour retrouver votre session.'}</Copy><Button title="Récupérer ma session" onPress={() => router.push('/photos')}/></View>
    <View style={s.card}><Copy style={{ fontWeight: '600' }}>Le miroir</Copy><Copy>{usesMirrorReader ? 'Votre carte est déjà inscrite ? Lancez un essayage avec le lecteur du miroir.' : 'Pour un essayage, connectez le miroir puis présentez votre carte au lecteur RC522. Gardez cet écran ouvert.'}</Copy>{usesMirrorReader ? <Button title="Essayer mes lunettes" onPress={() => router.push('/try-on')}/> : <><Status flow={mirror}/><Button title={state.busy ? 'Déconnecter le miroir' : 'Connecter le miroir'} onPress={() => { if (state.busy) mirror.stop(); else void mirror.start().catch(() => {}); }}/></>}<Copy style={{ fontSize: 13 }}>Version de test : les captures sont simulées.</Copy></View>
    {usesMirrorReader && <View style={s.card}>
      <Copy>Adresse Wi-Fi du miroir</Copy>
      <TextInput style={s.input} value={address} onChangeText={text => { setAddress(text); setAddressMessage(''); }}
        keyboardType="decimal-pad" autoCorrect={false} accessibilityLabel="Adresse Wi-Fi du miroir" />
      <Button secondary title="Utiliser cette adresse" onPress={() => {
        try {
          setWifiAddress(address);
          setAddressMessage('Adresse enregistrée pour cette ouverture de l’application.');
        } catch (error) {
          setAddressMessage(error instanceof Error ? error.message : 'Adresse invalide.');
        }
      }} />
      {!!addressMessage && <Copy>{addressMessage}</Copy>}
    </View>}
    <Button secondary title="Administration"  onPress={() => router.push('/admin')}/>
  </Page>;
}
