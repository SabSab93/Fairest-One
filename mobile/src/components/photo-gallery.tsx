import React, { useState } from 'react';
import { Image, Modal, Pressable, StyleSheet, Text, View } from 'react-native';
import { MailComposerStatus } from 'expo-mail-composer';
import { emailPhotos } from '../adapters/photo-mail';
import type { SessionPhoto } from '../core/types';
import { Button, colors, Copy, s } from './ui';

export function PhotoGallery({ email, photos }: { email: string; photos: SessionPhoto[] }) {
  const [selected, setSelected] = useState<Set<string>>(new Set());
  const [preview, setPreview] = useState<SessionPhoto>();
  const [sending, setSending] = useState(false);
  const [message, setMessage] = useState('');
  const allSelected = selected.size === photos.length;

  function toggle(id: string) {
    setSelected(current => {
      const next = new Set(current);
      if (!next.delete(id)) next.add(id);
      return next;
    });
  }

  async function send() {
    setSending(true);
    setMessage('');
    try {
      const status = await emailPhotos(email, photos.filter(photo => selected.has(photo.id)));
      if (status === MailComposerStatus.SENT) setMessage('Photos remises à votre messagerie.');
      if (status === MailComposerStatus.SAVED) setMessage('E-mail enregistré en brouillon.');
    } catch (error) {
      setMessage(error instanceof Error ? error.message : 'Impossible de préparer l’e-mail.');
    } finally {
      setSending(false);
    }
  }

  if (!photos.length) return <Copy>Aucune photo pour cette session.</Copy>;
  return <View style={s.card}>
    <Copy>{photos.length} {photos.length === 1 ? 'photo' : 'photos'}</Copy>
    <View style={styles.grid}>
      {photos.map((photo, index) => {
        const checked = selected.has(photo.id);
        return <View key={photo.id} style={styles.tile}>
          <Pressable onPress={() => setPreview(photo)} accessibilityRole="button" accessibilityLabel={`Agrandir la photo ${index + 1}`}>
            <Image source={{ uri: photo.url }} style={styles.thumbnail} resizeMode="cover" />
          </Pressable>
          <Pressable style={styles.check} disabled={sending} onPress={() => toggle(photo.id)}
            accessibilityRole="checkbox" accessibilityLabel={`Sélectionner la photo ${index + 1}`} accessibilityState={{ checked, disabled: sending }}>
            <Text style={styles.checkLabel}>{checked ? '✓ Sélectionnée' : 'Sélectionner'}</Text>
          </Pressable>
        </View>;
      })}
    </View>
    <Button secondary disabled={sending} title={allSelected ? 'Tout désélectionner' : 'Tout sélectionner'}
      onPress={() => setSelected(allSelected ? new Set() : new Set(photos.map(photo => photo.id)))} />
    <Button disabled={sending || selected.size === 0} title={sending ? 'Préparation de l’e-mail…' : `Envoyer par e-mail (${selected.size})`}
      onPress={() => { void send(); }} />
    {!!message && <Copy>{message}</Copy>}
    <Modal visible={!!preview} animationType="fade" onRequestClose={() => setPreview(undefined)}>
      <View style={styles.preview}>
        {preview && <Image source={{ uri: preview.url }} style={styles.fullImage} resizeMode="contain"
          accessible accessibilityLabel="Photo d’essayage agrandie" />}
        <Button title="Fermer la photo" onPress={() => setPreview(undefined)} />
      </View>
    </Modal>
  </View>;
}

const styles = StyleSheet.create({
  grid: { flexDirection: 'row', flexWrap: 'wrap', gap: 12 },
  tile: { width: '47%', minWidth: 100, flexGrow: 1 },
  thumbnail: { width: '100%', aspectRatio: 4 / 3, borderRadius: 8, backgroundColor: colors.paleSage },
  check: { minHeight: 44, justifyContent: 'center', alignItems: 'center' },
  checkLabel: { color: colors.ink, fontWeight: '600' },
  preview: { flex: 1, backgroundColor: colors.paper, padding: 24, paddingTop: 56, paddingBottom: 32, gap: 16 },
  fullImage: { flex: 1, width: '100%' },
});
