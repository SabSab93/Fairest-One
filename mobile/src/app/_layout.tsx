import React, { useEffect } from 'react';
import { AppState, ActivityIndicator, View } from 'react-native';
import { Stack } from 'expo-router';
import { useFonts } from 'expo-font';
import { StatusBar } from 'expo-status-bar';
import { stopHardware } from '../core/runtime';
import { colors, Copy } from '../components/ui';
export default function Layout() {
  const [loaded, error] = useFonts({ Cormorant: require('../../assets/fonts/CormorantGaramond-Variable.ttf') });
  useEffect(() => {
    const subscription = AppState.addEventListener('change', state => { if (state === 'background') stopHardware(); });
    return () => { subscription.remove(); stopHardware(); };
  }, []);
  if (!loaded && !error) return <View style={{ flex: 1, alignItems: 'center', justifyContent: 'center', backgroundColor: colors.paper }}><ActivityIndicator/><Copy>Fairest One</Copy></View>;
  return <><StatusBar style="dark"/><Stack screenOptions={{ headerShown: false, contentStyle: { backgroundColor: colors.paper } }}/></>;
}
