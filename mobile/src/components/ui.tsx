import React, { useSyncExternalStore } from 'react';
import { ActivityIndicator, Image, Pressable, ScrollView, StyleSheet, Text, View, type TextProps } from 'react-native';
import { router } from 'expo-router';
import { MaterialCommunityIcons } from '@expo/vector-icons';
import { SafeAreaView } from 'react-native-safe-area-context';
import type { Flow } from '../core/state';
export const colors = { ink: '#11100E', paper: '#FAF9F6', linen: '#E9E4DA', stone: '#C9BFAE', sage: '#71806E', paleSage: '#D9E0D5', dustyRose: '#E7D8D2', mist: '#F1F1EF' };
export function Copy(props: TextProps) { return <Text {...props} style={[s.copy, props.style]} />; }
export function Heading({ children }: React.PropsWithChildren) { return <Text accessibilityRole="header" style={s.heading}>{children}</Text>; }
export function Button({ title, onPress, disabled, secondary }: { title: string; onPress(): void; disabled?: boolean; secondary?: boolean }) {
  return <Pressable accessibilityRole="button" accessibilityState={{ disabled }} disabled={disabled} onPress={onPress} style={({ pressed }) => [s.button, secondary && s.secondary, { opacity: disabled ? .45 : pressed ? .7 : 1 }]}><Text style={[s.buttonText, secondary && { color: colors.ink }]}>{title}</Text></Pressable>;
}
export function Page({ children, back = true }: React.PropsWithChildren<{ back?: boolean }>) {
  return <SafeAreaView style={s.safe}><ScrollView keyboardShouldPersistTaps="handled" contentContainerStyle={s.page}><View style={s.header}><Pressable accessibilityRole="button" accessibilityLabel={back ? 'Retour à l’accueil' : 'Fairest One'} onPress={() => router.replace('/')} style={s.brand}>{back && <MaterialCommunityIcons name="arrow-left" size={25} color={colors.ink}/>}<View><Image source={require('../../assets/logo.png')} resizeMode="contain" accessibilityIgnoresInvertColors accessible={false} style={s.logo}/><Copy style={s.label}>BORNE D’ESSAYAGE</Copy></View></Pressable></View><View style={s.content}>{children}</View></ScrollView></SafeAreaView>;
}
export function Status({ flow }: { flow: Flow }) {
  const state = useSyncExternalStore(flow.subscribe, flow.getSnapshot, flow.getSnapshot);
  return <View accessibilityLiveRegion="polite" style={[s.status, state.stage === 'error' && { backgroundColor: colors.dustyRose }]}>{state.busy && <ActivityIndicator color={colors.sage}/>}<Copy style={{ flex: 1 }}>{state.message}</Copy></View>;
}
export const s = StyleSheet.create({
  safe: { flex: 1, backgroundColor: colors.paper }, page: { padding: 24, flexGrow: 1, alignItems: 'center' },
  header: { width: '100%', maxWidth: 980, borderBottomWidth: 1, borderColor: colors.linen, paddingBottom: 24, marginBottom: 38 },
  brand: { flexDirection: 'row', alignItems: 'center', gap: 14, alignSelf: 'flex-start', minHeight: 48 }, logo: { width: 176, height: 88 },
  label: { fontSize: 10, letterSpacing: 2, marginTop: 4 }, content: { width: '100%', maxWidth: 560, gap: 22, paddingBottom: 32 },
  heading: { fontFamily: 'Cormorant', fontSize: 60, lineHeight: 64, color: colors.ink }, copy: { fontSize: 16, lineHeight: 24, color: colors.ink },
  button: { minHeight: 54, padding: 16, backgroundColor: colors.ink, borderRadius: 8, alignItems: 'center', justifyContent: 'center' },
  secondary: { backgroundColor: colors.linen }, buttonText: { color: colors.paper, fontSize: 13, letterSpacing: 1.5, textAlign: 'center', fontWeight: '600' },
  input: { borderWidth: 1, borderColor: colors.stone, borderRadius: 8, backgroundColor: 'white', minHeight: 56, padding: 16, color: colors.ink, fontSize: 16 },
  card: { padding: 24, backgroundColor: colors.mist, borderRadius: 12, gap: 14 }, status: { padding: 16, borderRadius: 8, backgroundColor: colors.linen, flexDirection: 'row', gap: 12, alignItems: 'center' },
});
