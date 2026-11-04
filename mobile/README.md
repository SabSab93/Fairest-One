# Fairest One — Expo / EAS

Application React Native distincte dans `mobile/`. Flutter, l’API Vercel, Supabase et le firmware existants sont conservés. Aucun déploiement, flashage ou changement de base distante n’est lancé par ce projet.

## Parcours repris

- **Nouveau client** : e-mail → lecture NFC du téléphone → association via l’API.
- **Essayage** : accueil ouvert → connexion BLE au miroir → carte sur RC522 → validation backend → LED/bips/compte à rebours → capture simulée → enregistrement backend.
- **Récupération** : lecture NFC du téléphone → vérification de l’accès personnel → affichage des messages de la session.
- **Administration** : mot de passe vérifié par l’API, clients, compteurs de captures et accès aux informations de logs. Les vraies photos et l’envoi par e-mail ne sont pas encore implémentés dans le projet existant.

Le thème, la police Cormorant Garamond et l’icône reprennent Flutter. Le navigateur permet un aperçu des écrans ; les actions NFC et BLE nécessitent une application native personnalisée, et ne fonctionnent pas dans Expo Go.

## Préparation, quand vous serez prête

1. Fournir et valider une **URL d’API de test**. Aucun lien de production n’est préconfiguré. L’API doit contenir les actions `begin_phone_registration`, `begin_phone_recovery`, `phone_scan`, `phone_cancel`, ainsi que les actions miroir existantes. Les migrations locales `../docs/supabase-nfc.sql` et `../docs/supabase-phone-nfc.sql` doivent avoir été vérifiées et appliquées à cette base de test par une personne autorisée. Aucune modification API supplémentaire n’est nécessaire pour Expo.
2. Ouvrir le Terminal sur le Mac :

```sh
cd /Users/sabrina/dev/annee5/Fairest-One/mobile
export PATH="/opt/homebrew/opt/node@24/bin:$PATH"
npm ci
npx eas-cli@latest login
npx eas-cli@latest init
```

`login` se fait avec votre compte Expo. `init` associe ce dossier à votre projet Expo et ajoute son identifiant à `app.json`. Conservez vos mots de passe pour vous. Node 24 est déjà présent sur ce Mac ; sur un autre ordinateur, installer une version compatible avec Expo SDK 57.

3. Configurer la variable **publique** du build de test dans Expo :

```sh
npx eas-cli@latest env:create --environment preview --name EXPO_PUBLIC_API_URL --value https://VOTRE-PREVIEW.vercel.app/api/ --visibility plaintext
```

Remplacer l’exemple par l’URL approuvée, avec `/api/` à la fin. La variable est intégrée au JavaScript : n’y mettre aucune clé Supabase, clé miroir ou mot de passe. Le build refuse une URL absente, non HTTPS ou mal formée.

4. Contrôler l’archive locale avant le premier envoi :

```sh
npx eas-cli@latest build:inspect --platform android --profile preview --stage archive --output /tmp/fairest-expo-archive
```

Le `.easignore` **à la racine du dépôt** autorise uniquement les sources/configurations/assets nécessaires de `mobile/`. Les `.env`, clés, `node_modules`, API, Flutter, base SQL et `firmware/config.h` ne doivent pas apparaître dans l’archive. Les répertoires natifs sont générés par Expo à chaque build.

## Android : version simple à installer

```sh
npx eas-cli@latest build --platform android --profile preview
```

Ce profil produit un **APK autonome**, sans Metro ni ordinateur à garder allumé. À la fin, ouvrir le lien EAS sur le Xiaomi et installer l’APK. Si Android le demande, autoriser l’installation depuis la source utilisée. Aucun compte Google Play n’est nécessaire pour ce test. Les quotas/offres EAS peuvent évoluer : vérifier ce qu’Expo affiche avant de lancer un build payant.

Sur Xiaomi : activer le NFC dans les réglages (chercher « NFC »), activer Bluetooth puis autoriser **Appareils à proximité** à Fairest One. Sur Android 11 ou antérieur, la recherche BLE demande l’autorisation et parfois l’activation de la localisation. Pour installer un APK EAS, le débogage USB et Android Studio ne sont pas nécessaires. Le modèle Xiaomi doit réellement disposer du NFC ; certaines variantes n’en possèdent pas.

## iPhone : version personnalisée signée

```sh
npx eas-cli@latest device:create
npx eas-cli@latest build --platform ios --profile preview
```

Ouvrir le lien d’enregistrement sur l’iPhone à tester, enregistrer cet appareil, puis sélectionner cet appareil lors de la création du profil. Utiliser une **équipe Apple Developer éligible au NFC** : la Personal Team gratuite affichée précédemment refuse `NFC Tag Reading`. Expo/EAS ne contourne pas cette restriction. Aucun achat n’est effectué automatiquement.

Installer depuis le lien fourni par EAS et suivre les instructions de confiance/mode développeur si iOS les demande. Autoriser Bluetooth. Pour le NFC, appuyer sur « Lire ma carte NFC » ou « Scanner ma carte », puis tenir la carte près du haut de l’iPhone pendant la session de lecture système. Le NFC n’est pas déclenché par le lien Safari et ne se teste pas dans un simulateur.

## Pendant le développement

Le profil `development` inclut le client de développement Expo et demande Metro :

```sh
npx eas-cli@latest env:create --environment development --name EXPO_PUBLIC_API_URL --value https://VOTRE-PREVIEW.vercel.app/api/ --visibility plaintext
npx eas-cli@latest build --platform android --profile development
# ou --platform ios, après l’enregistrement de l’appareil
cp .env.local.example .env.local
# Renseigner la même URL de test dans .env.local
npm start
```

Téléphone et Mac sur le même réseau pour Metro, ou utiliser le tunnel Expo si nécessaire. Cela concerne le développement de l’application ; **le miroir reste exclusivement en BLE**. Après ajout d’une dépendance native ou modification des autorisations, reconstruire le client.

`npm run web` affiche un aperçu sans matériel. `npm run android` / `npm run ios` sont les alternatives de compilation locale avec Android Studio / Xcode. EAS cloud fournit ces outils ; CocoaPods n’est pas installé sur ce Mac et n’est pas requis pour le build iOS cloud.

## Sécurité et protocole existant

- L’UID n’est pas une authentification forte. Un accès aléatoire personnel de 256 bits est conservé dans **Expo SecureStore**, jamais dans une variable publique ou les logs. Seul son hash est lié au client côté serveur.
- La récupération demande **la même installation de l’application sur le même téléphone**. Expo et Flutter ont des identifiants/stockages différents : les accès Flutter ne sont pas transférés automatiquement. Pour le premier test Expo, utiliser une carte et un e-mail encore libres dans la base de test, ou préparer une réassociation autorisée côté backend. Ne jamais reprendre une carte déjà affectée en contournant les contrôles.
- Réinstallation, effacement ou perte des données peut faire perdre l’accès ; aucune récupération par UID seul n’est ajoutée.
- Le mot de passe administrateur reste en mémoire et est effacé à la sortie de l’écran ou au passage en arrière-plan.
- Requêtes HTTPS limitées à 10 secondes, lecture NFC à 45 secondes, attente BLE à 35 secondes. Annulation explicite, fin de lecture à la sortie de l’écran et arrêt du matériel en arrière-plan. Reconnexion BLE manuelle après erreur ; aucune capture sans validation serveur.
- Le firmware du dépôt `../firmware/fairest_one/fairest_one.ino` reste nécessaire. Un ancien sketch de test qui envoie seulement un UID sans preuve n’est pas compatible avec ces contrôles. Aucun GPIO n’est modifié par ce portage.

| Service / caractéristique | UUID |
|---|---|
| Service | `83de1000-7a28-4b54-9815-47c0ae451001` |
| Notifications | `83de1001-7a28-4b54-9815-47c0ae451001` |
| Écriture avec réponse | `83de1002-7a28-4b54-9815-47c0ae451001` |

JSON UTF-8 terminé par `\n`, fragments de 20 octets, corrélation par défi `token`. Le téléphone relaie `card_scanned` puis `capture_simulated` avec leur preuve HMAC distincte. La clé de signature reste dans le firmware et Vercel. Voir [le protocole détaillé](../docs/ble-integration.md). Anti-rebond assuré par le firmware : retirer la carte au moins 600 ms avant de la représenter.

## Validation et tests des deux cartes

Contrôles logiciels effectués le 4 novembre 2026 : TypeScript, lint, 13 tests unitaires de flux/transports, 6 tests de l’API existante, génération des autorisations natives et export JavaScript/Hermes Android + iOS + web. `expo-doctor` : 20/21 contrôles passent ; le contrôle CocoaPods local échoue car l’outil n’est pas installé. Les versions de modules sont validées par `expo install --check`.

**Pas encore effectués** : build natif signé EAS, installation et lecture physique des cartes, contrôle visuel dans un navigateur (outil indisponible). EAS n’est pas connecté ; l’URL de test doit encore être fournie. L’inspection EAS complète demande aussi cette connexion ; la sélection locale des fichiers par `.easignore` a été contrôlée.

L’audit npm conserve des alertes dans les dépendances Expo/Router et les outils, dont des alertes élevées (`decode-uri-component`, `zod`). `npm audit fix --ignore-scripts` n’a pas apporté de correctif compatible à toutes ces alertes. Ne pas utiliser `--force` : il propose notamment un changement de SDK incompatible. Réévaluer les correctifs avant diffusion publique ; ce portage est destiné aux tests internes.

| Test matériel à réaliser sur chaque plateforme | Résultat attendu | État |
|---|---|---|
| Inscrire carte A + e-mail de test depuis le téléphone | Confirmation, une association | À faire |
| Refaire l’inscription carte A / e-mail existant | Refus de doublon | À faire |
| Connecter miroir, présenter carte A | LED verte, 2 bips, compte à rebours, un message enregistré | À faire |
| Présenter carte B non inscrite | LED rouge, 3 bips, aucun message supplémentaire | À faire |
| Récupérer carte A sur la même installation Expo | Messages de la session affichés | À faire |
| Récupérer carte A sur un autre téléphone | Refus, aucune donnée personnelle affichée | À faire |
| Maintenir carte A sur RC522 | Aucun doublon jusqu’au retrait de la carte | À faire |
| Couper Bluetooth / quitter l’accueil / mettre en arrière-plan | Parcours interrompu, aucune capture non autorisée | À faire |
| Couper Internet avant confirmation du backend | Erreur visible, aucun feu vert | À faire |
| Refuser Bluetooth / désactiver NFC / ne présenter aucune carte | Erreur explicite ou timeout, possibilité de relancer | À faire |

Commandes locales : `npm run typecheck`, `npm run lint`, `npm test`. API : `npm run test:api` depuis la racine.

Références officielles : [client de développement](https://docs.expo.dev/develop/development-builds/introduction/), [distribution interne](https://docs.expo.dev/build/internal-distribution/), [NFC](https://github.com/revtel/react-native-nfc-manager), [BLE](https://github.com/dotintent/react-native-ble-plx).
