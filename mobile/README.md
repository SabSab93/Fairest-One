# Fairest One — application Expo iPhone / lecteur BLE

Le choix actuel est une application iPhone simple, avec **le RC522 du miroir pour toutes les lectures de cartes**. L’iPhone communique exclusivement en BLE avec l’ESP32-C6, et en HTTPS avec l’API Vercel. Le Wi-Fi n’est pas utilisé sur l’ESP32. L’USB sert à la programmation et aux logs du matériel.

Les écrans, le logo, l’API Vercel, Supabase et le firmware existants sont réutilisés. Flutter et le parcours Android natif restent dans le dépôt. Aucun déploiement de backend, changement de base distante ou flashage du matériel n’est automatique.

## Utilisation sur iPhone

1. **Nouveau client** : saisir l’e-mail, appuyer sur « Associer ma carte avec le miroir », autoriser Bluetooth puis présenter la carte au RC522. L’application associe l’e-mail et la carte via le backend et affiche la confirmation. Cette opération ne déclenche aucune capture.
2. **Essayage** : depuis l’accueil, appuyer sur « Connecter le miroir » et présenter la carte au RC522. Le backend doit reconnaître la carte avant le feu vert, les deux bips et le compte à rebours. Le message de capture simulée est ensuite enregistré. Garder cet écran ouvert.
3. **Récupération** : ouvrir « Récupérer ma session », appuyer sur « Lire ma carte sur le miroir » et présenter la carte au même RC522. Les messages de la session apparaissent sur l’iPhone. Cette opération ne déclenche aucune capture.

Retirer la carte au moins 600 ms entre deux passages. Le lecteur n’est armé que pendant une demande de l’application. Une seule opération utilise le miroir à la fois. Quitter l’écran ou mettre l’app en arrière-plan annule l’opération ; une déconnexion demande une nouvelle tentative.

Les captures sont encore **simulées** : aucune vraie photo ni envoi d’e-mail n’est implémenté. L’administration reprend la liste des clients, les compteurs et les informations de logs du projet existant.

## Installer localement avec Xcode

La configuration iOS ne demande plus `NFC Tag Reading` ni `NFCReaderUsageDescription`. Le NFC est lu par le RC522, jamais par Core NFC dans ce parcours. Le mode lecteur Android reste disponible, avec sa permission NFC déclarée explicitement.

Un compte Apple gratuit permet de signer localement cette version BLE sur son propre iPhone. La signature gratuite expire après 7 jours : il faut alors reconstruire et réinstaller depuis le Mac. EAS/TestFlight pour un appareil iOS réel restent liés à une adhésion Apple Developer adaptée ; Expo Go ne contient pas notre bibliothèque BLE native.

1. Brancher l’iPhone au Mac, le déverrouiller et accepter « Faire confiance à cet ordinateur ».
2. Activer **Réglages → Confidentialité et sécurité → Mode développeur**, redémarrer et confirmer son activation.
3. Sur le Mac :

```sh
cd /Users/sabrina/dev/annee5/Fairest-One/mobile
export PATH="/opt/homebrew/opt/node@24/bin:/opt/homebrew/bin:$PATH"
npm ci
cp .env.local.example .env.local
# Renseigner EXPO_PUBLIC_API_URL dans .env.local.
# URL actuellement approuvée : https://fairest-one-documentation.vercel.app/api/
npx expo prebuild --platform ios --clean
npx expo run:ios --device --configuration Release
```

La version **Release** embarque le JavaScript : après installation, le Mac et Metro ne sont pas nécessaires pendant l’utilisation. Pour le développement avec rechargement rapide, utiliser `npx expo run:ios --device`, puis `npm start` avec l’iPhone sur le même réseau que le Mac.

L’espace de travail est `ios/FairestOne.xcworkspace`. Dans Xcode, sélectionner l’iPhone réel et l’équipe Apple dans **Signing & Capabilities**, puis lancer la compilation. Le projet Flutter `ios/Runner.xcworkspace` est distinct : ouvrir celui de `mobile/` pour Expo.

Les répertoires natifs sont générés et ignorés par Git : ne pas les éditer à la main pour modifier durablement une permission. Utiliser `app.json` et les plugins Expo, puis régénérer iOS.

## Backend : configuration nécessaire

L’application utilise `https://fairest-one-documentation.vercel.app/api/`. Malgré son nom, cette adresse expose bien `/api/clients`. L’URL est publique ; aucune clé Supabase ou miroir n’est embarquée dans l’application.

L’API Vercel doit disposer de :

- `SUPABASE_URL` du bon projet ;
- `SUPABASE_SECRET_KEY` contenant une **clé serveur secrète** `sb_secret_…` ou une ancienne clé `service_role`, jamais `sb_publishable_…` ;
- `MIRROR_DEVICE_ID`, identifiant du miroir, différent de `native-ios` ;
- `MIRROR_SIGNING_KEY`, chaîne privée d’au moins 32 caractères ASCII, identique à celle du firmware ;
- `ADMIN_PASSWORD` pour l’administration.

La clé configurée actuellement dans Vercel a été signalée par Sabrina comme `sb_publishable_…` : **elle doit être corrigée côté serveur avant de valider les enregistrements**. Ne pas partager les valeurs secrètes dans le chat et ne jamais les placer dans `EXPO_PUBLIC_*`. Un changement de variable Vercel nécessite un redéploiement du backend après validation ; il ne nécessite pas un nouveau build de l’application si l’URL reste identique.

L’e-mail est stocké dans **Table Editor → public.clients.email**, pas dans Authentication → Users. Les logs seuls ne prouvent pas la création du client. L’association est réalisée seulement après la lecture de carte signée et la validation du backend.

Les tables/fonctions de `../docs/supabase-schema.sql` et `../docs/supabase-nfc.sql` doivent être en place dans le projet Supabase visé. Vérifier et valider ces migrations avant toute application à une base existante. Aucun changement d’API ou de schéma supplémentaire n’est nécessaire pour le parcours iOS tout-BLE.

## Firmware et protocole

Utiliser le programme complet `../firmware/fairest_one/fairest_one.ino`, avec un `config.h` préparé à partir de `config.example.h` : clé privée de signature et PIN BLE personnel à six chiffres. Les GPIO existants sont conservés. Aucun flashage n’est réalisé automatiquement.

Un ancien sketch de test qui annonce d’autres UUID ou transmet seulement `{"type":"card_scanned","uid":"…"}` n’est pas compatible avec le protocole signé de l’application et du backend.

| Élément | UUID |
|---|---|
| Service | `83de1000-7a28-4b54-9815-47c0ae451001` |
| Notifications | `83de1001-7a28-4b54-9815-47c0ae451001` |
| Écritures avec réponse | `83de1002-7a28-4b54-9815-47c0ae451001` |

JSON UTF-8 terminé par `\n`, fragments de 20 octets, événements corrélés par défi temporaire `token`. L’app réutilise `begin_registration`, `begin_recovery`, `begin_recognition`, `scan`, `capture` et `cancel` sur `POST /api/clients`. Le firmware produit des preuves HMAC avec des domaines distincts pour lecture et capture. La clé reste dans Vercel et le firmware. Voir [le protocole complet](../docs/ble-integration.md).

L’inscription et la récupération confirment la carte avec `recognized:true,capture:false`. Seul l’essayage reconnu envoie `capture:true`. Une erreur backend, un mauvais défi ou une preuve absente ne déclenche aucune capture. La présence d’un UID NFC n’est pas une authentification forte ; dans ce mode, le backend autorise la récupération sur une lecture physique signée du miroir de confiance.

## Android et EAS conservés

Android garde la lecture NFC du téléphone et l’accès personnel SecureStore pour l’inscription/récupération. Ce stockage est propre à l’installation : ne pas désinstaller l’application pour faire une mise à jour. Sur iOS, le parcours tout-BLE utilise l’autorisation signée du miroir et n’exige pas ce jeton du téléphone.

Le projet EAS est `@sabristiti/fairest-one`, ID `4e1ed398-0f6f-4c39-9841-94f4fbaf5c38`. Les profils `preview` (autonome) et `development` (Metro) restent dans `eas.json`. Les builds Android déjà envoyés sont des instantanés de leur code ; les modifications locales ultérieures ne les modifient pas.

Le `.easignore` à la racine autorise les seules sources/configurations/assets nécessaires de `mobile/`, sans `.env`, backend, Flutter, base SQL, clés, `firmware/config.h` ou `node_modules`. L’archive complète a été inspectée avant le premier envoi.

## Vérifications

TypeScript, lint, 22 tests de flux/transports passent, dont inscription et récupération via miroir, preuve absente, mauvais défi, refus backend, carte inconnue, annulation et exclusion des opérations simultanées. L’export iOS passe. La génération iOS produit un fichier d’entitlements sans autorisation NFC.

La compilation native iOS Release sans signature a réussi, avec un bundle JavaScript embarqué. La signature et l’installation attendent l’activation du mode développeur sur l’iPhone connecté. Les tests BLE sur le matériel réel restent à effectuer ; ne pas déduire leur résultat des tests logiciels. Un contrôle sans écriture de l’API active a reçu HTTP 503 « Configuration serveur incomplète » : vérifier les variables et l’environnement Vercel du domaine réellement utilisé avant les enregistrements.

Les alertes npm de dépendances Expo/Router et d’outils restent à réévaluer avant diffusion publique. Ne pas appliquer `npm audit fix --force`, qui propose des changements de SDK incompatibles.

| Test physique | Attendu |
|---|---|
| Inscrire carte A + e-mail via RC522 | Un client associé, sans capture |
| Réinscrire carte A / e-mail existant | Refus de doublon |
| Essayage avec carte A | Vert, 2 bips, compte à rebours et un message |
| Essayage avec carte B inconnue | Rouge, 3 bips, aucun message supplémentaire |
| Récupérer carte A via RC522 | Messages de la session sur l’iPhone, sans capture |
| Maintenir carte A devant RC522 | Pas de doublons jusqu’au retrait |
| Couper Bluetooth / quitter l’écran / arrière-plan | Annulation, sans capture non autorisée |
| Erreur backend / preuve invalide | Erreur affichée, aucun feu vert pour une capture |

Commandes : `npm run typecheck`, `npm run lint`, `npm test`. Les tests de l’API existante se lancent avec `npm run test:api` depuis la racine.

Références : [développement local Expo](https://docs.expo.dev/develop/development-builds/introduction/), [signature Apple gratuite et limites](https://expo.dev/blog/apple-developer-program-explained-free-vs-paid), [clés Supabase](https://supabase.com/docs/guides/getting-started/api-keys).
