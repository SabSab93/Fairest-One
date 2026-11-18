import { Directory, File, Paths } from 'expo-file-system';
import * as MailComposer from 'expo-mail-composer';
import { Platform } from 'react-native';
import type { SessionPhoto } from '../core/types';

export async function emailPhotos(recipient: string, photos: SessionPhoto[]) {
  if (Platform.OS === 'web' || !await MailComposer.isAvailableAsync()) {
    throw new Error('Configurez une application de messagerie sur votre téléphone pour joindre les photos.');
  }
  const cache = new Directory(Paths.cache, 'fairest-photo-mail');
  cache.create({ idempotent: true });
  for (const previous of cache.list()) {
    if (previous instanceof Directory && Date.now() - Number(previous.name) > 24 * 60 * 60 * 1000) previous.delete();
  }
  const folder = new Directory(cache, String(Date.now()));
  folder.create();
  let handedToMail = false;
  try {
    const attachments: string[] = [];
    for (const [index, photo] of photos.entries()) {
      const file = await File.downloadFileAsync(photo.url, new File(folder, `essayage-${index + 1}.jpg`));
      attachments.push(file.uri);
    }
    const result = await MailComposer.composeAsync({
      recipients: [recipient],
      subject: 'Vos photos d’essayage Fairest One',
      body: 'Bonjour, voici les photos de votre essayage.',
      attachments,
    });
    handedToMail = true;
    return result.status;
  } finally {
    // On Android the mail client receives file URIs and may still read them.
    if (Platform.OS === 'ios' || !handedToMail) folder.delete();
  }
}
