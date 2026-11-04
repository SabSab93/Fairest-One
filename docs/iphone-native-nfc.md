# Lecture NFC native sur iPhone — inscription et récupération

**Support Android ajouté :** le même service lit aussi les NTAG215 sur Android. Le [guide Android](android-native-nfc.md) décrit l’installation et les tests gratuits sur téléphone. Les explications ci-dessous restent spécifiques à iOS.

Cette évolution réutilise les écrans, la navigation, `ClientRecord`, `ApiClient`, l'endpoint Vercel `/api/clients` et les tables Supabase. Branche : `feat/iphone-native-nfc`.

## Parcours actuel

```text
Inscription / récupération : carte NTAG215 → NFC de l’iPhone → API HTTPS → Supabase
Essayage : carte → RC522 → ESP32-C6 → BLE → iPhone → API HTTPS → Supabase
```

L'inscription et la récupération ne demandent plus de connexion au miroir. La lecture se lance depuis un bouton de l'application installée : Core NFC ouvre sa fenêtre système, puis on approche la carte du **haut de l'iPhone**. Aucune donnée n'est écrite sur la carte. L'UID est converti en hexadécimal majuscule, octet par octet, avec les zéros initiaux, comme sur le RC522.

L'essayage au miroir conserve son firmware BLE et sa signature HMAC. L'app doit rester ouverte, reliée au miroir et connectée à Internet pendant les captures. Les photos sont toujours des **messages simulés**, en attendant une caméra.

Safari ne permet pas ce parcours NFC ni le BLE du miroir. Ajouter le site à l'écran d'accueil ne suffit pas. Le build web est conservé ; une tentative de lecture y affiche une indication vers l'application iPhone installée.

## Protection de la récupération sur le même iPhone

C'est le périmètre confirmé pour ce prototype : inscription et récupération sur **le même iPhone**.

- Lors de la première inscription, l'app crée un jeton personnel aléatoire de 256 bits et le conserve dans le **trousseau iOS**, accessible uniquement lorsque l'appareil est déverrouillé, sans synchronisation iCloud ni migration de ce jeton vers un autre appareil.
- Le stockage est vérifié **avant** toute inscription envoyée au backend. Une panne réseau ou une réponse perdue ne doit pas faire perdre l'accès à un client déjà créé.
- Chaque inscription lie le client au SHA-256 de ce jeton. Plusieurs cartes inscrites sur ce même iPhone peuvent être utilisées pour ce test.
- La récupération exige la carte, ce jeton personnel et une demande serveur de **90 secondes à usage unique**. Connaître uniquement l'UID ne rend ni les e-mails ni les captures.
- Le serveur ne reçoit aucune preuve HMAC du miroir pour ces lectures. Il ne peut pas attester qu'une requête HTTP provient réellement du lecteur NFC iOS. L'autorisation repose sur le jeton personnel, pas sur une prétendue inviolabilité de l'UID.
- Aucune clé Supabase secrète, aucun mot de passe admin et aucune clé de signature du miroir ne sont embarqués dans Flutter. Le jeton personnel est une autorisation créée à l'exécution pour cet iPhone, jamais une constante du code ou un `--dart-define`.
- Toutes les requêtes natives exigent une URL API **HTTPS** ; elles utilisent la validation TLS normale du système.

La récupération sur un autre iPhone, la perte du jeton et le rattachement de clients inscrits uniquement avec l'ancien parcours BLE nécessitent une réautorisation sécurisée. Aucun transfert d'accès par UID seul ni réinitialisation publique du jeton n'est ajouté. Pour le premier test natif, utiliser une carte/e-mail encore disponibles dans la base de **test**, sans supprimer les données existantes. L'ancien parcours BLE reste accessible avec `--dart-define=USE_PHONE_NFC=false`.

## Fichiers et dépendances

| Fichier | Rôle |
|---|---|
| `lib/features/nfc/data/phone_nfc_reader.dart` | Core NFC, lecture du UID MIFARE/NTAG, annulation, disponibilité et timeout ; aucune écriture NDEF |
| `lib/features/nfc/data/phone_access_store.dart` | Jeton personnel aléatoire conservé dans le trousseau |
| `lib/features/nfc/data/phone_nfc_flow_controller.dart` | Coordonne lecture, stockage et demandes HTTP ; annule en arrière-plan |
| `registration_screen.dart` / `photo_recovery_screen.dart` | Écrans existants reliés au NFC du téléphone par défaut, états d'attente/erreur conservés |
| `api/clients.mjs` | Actions téléphone dans l'endpoint existant ; les opérations miroir gardent leurs signatures |
| `docs/supabase-phone-nfc.sql` | Migration additionnelle à valider et appliquer sur le projet de test |
| `ios/Runner/Info.plist` / `Runner.entitlements` / projet Xcode | Description de l'usage NFC, droit `TAG`, trousseau et configuration des trois builds Runner |

Dépendances ajoutées et figées :

- [`nfc_manager` 4.2.1](https://pub.dev/packages/nfc_manager/versions/4.2.1), iOS minimum 13.0 ; le projet cible déjà iOS 15.0.
- [`flutter_secure_storage` 10.3.1](https://pub.dev/packages/flutter_secure_storage/versions/10.3.1), pour le trousseau. Son implémentation Darwin résolue est compatible avec la cible iOS du projet.

La fenêtre NFC peut rendre l'app **inactive** : cet état ne doit pas annuler la lecture. L'annulation intervient quand l'app passe réellement en arrière-plan (`paused`), quitte l'écran ou reçoit une annulation du système. Une seule lecture est traitée à la fois. Délai de lecture : 45 s ; les demandes HTTP conservent leur timeout de 10 s.

## Migration SQL et API — aucune application automatique

Faire relire et appliquer **sur Supabase de test**, dans cet ordre :

1. `supabase-schema.sql` **uniquement si les tables de départ n'existent pas** ; sinon comparer le schéma réel.
2. `supabase-nfc.sql` pour le parcours miroir existant et les captures simulées, si pas encore appliqué.
3. [`supabase-phone-nfc.sql`](supabase-phone-nfc.sql) pour les lectures natives.

La nouvelle migration ajoute `mobile_access_hash` dans `clients` et `nfc_requests`, puis crée `phone_nfc_operation`. Cette fonction réutilise `nfc_operation` pour créer le client, la session et récupérer les messages. Les lignes existantes sont préservées. Le rôle `anon` et les clients Flutter n'ont pas le droit d'appeler cette fonction directement ; seul le rôle serveur `service_role` le peut.

Les e-mails restent dans `clients.email`, les UID dans `clients.card_uid`, les sessions dans `sessions` et les captures dans `photos`. La création d'un client et sa session, ainsi que l'association du jeton personnel, s'effectuent dans la même transaction. Une relance du même enregistrement après perte de réponse ne crée pas de doublon ni ne remplace le propriétaire d'une carte.

Toutes les actions passent par **POST `/api/clients`** :

| Action | Entrée | Sortie |
|---|---|---|
| `begin_phone_registration` | `email`, `mobile_token` personnel | `token` de demande temporaire, `expires_in:90` |
| `begin_phone_recovery` | `mobile_token` | Demande temporaire |
| `phone_scan` | `token`, `mobile_token`, `card_uid` | `associated`, `failed` (doublon) ou `recovered` avec le client/messages autorisés |
| `phone_cancel` | `token`, `mobile_token` | Annulation de la demande encore active |

Une récupération sans le bon jeton renvoie **403**, de manière identique pour une carte inconnue, une carte d'un autre iPhone et un ancien client BLE sans accès natif. Une demande expirée/consommée renvoie **410**. Les anciens `GET ?card_uid=…` restent réservés à l'administrateur. La reconnaissance et la capture au miroir exigent toujours leur preuve HMAC.

`native-ios` est un espace de demandes réservé au téléphone : ne pas l'utiliser comme `MIRROR_DEVICE_ID`. Les opérations natives n'ont pas besoin de `MIRROR_SIGNING_KEY` ; le serveur doit toujours disposer de ses variables Supabase. Le jeton personnel brut n'est pas conservé dans Supabase et n'est pas renvoyé dans une réponse de récupération.

Il faut rendre disponible **manuellement**, après validation, une API de test contenant les nouveaux changements. L'ancienne Preview Vercel n'acquiert pas automatiquement ces actions. Aucun déploiement et aucune modification de base distante ne sont effectués par cette étape de développement.

## Xcode s'installe sur le Mac

L'iPhone reçoit l'application Fairest-One, **pas Xcode**. Il n'est pas nécessaire de publier sur l'App Store pour tester localement. La signature et le profil doivent toutefois autoriser la capacité NFC utilisée par l'app. Les capacités disponibles dépendent de l'équipe et de l'adhésion Apple ; vérifier ce point dans [la référence Apple](https://developer.apple.com/help/account/reference/supported-capabilities-ios) avant toute souscription. Si Xcode indique qu'une équipe personnelle ne supporte pas le NFC, utiliser une équipe autorisée, par exemple celle de l'école si elle en propose une.

Après installation sur le Mac :

1. Ouvrir Xcode et terminer l'installation de ses composants, du SDK iOS et l'acceptation de ses licences.
2. Vérifier que les outils utilisent Xcode complet :

```sh
xcode-select -p
# Attendu : /Applications/Xcode.app/Contents/Developer
flutter doctor -v
```

Si un autre chemin est sélectionné, choisir Xcode dans ses réglages **Locations → Command Line Tools**, ou exécuter manuellement :

```sh
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -runFirstLaunch
```

3. Depuis le dépôt, exécuter `flutter pub get`, puis ouvrir `ios/Runner.xcworkspace`. Le projet utilise Swift Package Manager pour ses plugins ; suivre les éventuels prérequis signalés par `flutter doctor`.
4. Cible **Runner → Signing & Capabilities** : choisir l'équipe de signature autorisée, un Bundle Identifier unique, et vérifier **Near Field Communication Tag Reading** ainsi que **Keychain Sharing**. Le fichier `Runner.entitlements` est déjà référencé pour Debug, Profile et Release, avec le format NFC `TAG` et un groupe de trousseau vide (stockage privé de l'app, pas de partage inter-apps).
5. La description `NFCReaderUsageDescription` est déjà ajoutée. Aucun identifiant d'application ISO7816 ni code FeliCa n'est requis pour le NTAG215 : le lecteur demande uniquement `iso14443`.
6. Brancher l'iPhone au Mac, le déverrouiller, approuver le Mac et activer **Réglages → Confidentialité et sécurité → Mode développeur** si demandé. Redémarrer et confirmer le mode développeur si iOS le demande. Voir [les étapes officielles Flutter](https://docs.flutter.dev/platform-integration/ios/setup).
7. Une fois l'API de test et les migrations validées/configurées :

```sh
flutter devices
flutter run -d <IDENTIFIANT_IPHONE> \
  --dart-define=APP_API_URL=https://VOTRE_API_TEST.vercel.app/api/
```

Le `/api/` final est nécessaire. Ne pas ajouter de secret dans cette commande. L'installation de cette app native ne remplace pas le site Vercel ; l'API reste hébergée sur Vercel.

## Test sur iPhone avec les NTAG215

1. Lancer **l'app installée**, puis Nouvelle session. Saisir un nouvel e-mail de test et toucher **CRÉER LA SESSION** ou l'icône NFC. Approcher la carte A du haut de l'iPhone quand la fenêtre système apparaît. Attendre la confirmation.
2. Vérifier le client, la session et `mobile_access_hash` non nul sur Supabase de test. Le jeton lui-même ne doit pas apparaître dans les tables.
3. Revenir au tableau de bord, lancer **CONNECTER LE MIROIR · ESSAYAGE** et accepter l'appairage BLE avec son PIN si nécessaire. Présenter A au RC522, puis retirer la carte entre les lectures. Répéter trois fois. Les signaux et captures restent ceux du guide BLE.
4. Carte B non associée au RC522 : LED rouge, trois bips, aucune capture. Ne pas l'inscrire si l'on souhaite garder ce test de refus.
5. Ouvrir Récupérer mes photos → **LIRE LA CARTE**. Présenter A **à l'iPhone**, sans lecteur RC522. Les trois messages doivent apparaître.
6. Relancer l'app et récupérer à nouveau avec A : l'accès personnel doit rester présent dans le trousseau.
7. Annuler la fenêtre NFC, ne pas présenter de carte, passer en arrière-plan et couper Internet : message d'erreur explicite, aucune fausse confirmation ni doublon d'inscription.
8. Vérifier avec un autre jeton dans un environnement de test qu'un UID connu ne suffit pas à récupérer les données. Ne pas effacer le jeton du vrai iPhone de test pour ce contrôle.

## Vérifications

- 45 tests Flutter : parcours natifs et BLE simulés, écrans existants, format UID, persistance avant inscription, relance d'enregistrement, refus d'accès, annulation, timeout, arrière-plan et exigence HTTPS.
- 6 tests API Node : validation, séparation téléphone/miroir et absence d'exposition des secrets.
- Scénarios PostgreSQL sur une base **locale jetable** : inscription native → trois captures avec le parcours miroir existant → récupération native, usage unique, expiration, refus d'un autre jeton et conservation du propriétaire.
- Fichiers plist, entitlements et projet Xcode vérifiés avec `plutil`.
- Compilation iOS Debug réussie avec Xcode 27.2 **sans signature**, avec une URL API fictive de compilation. Ce binaire ne doit pas être utilisé tel quel pour le test : relancer avec la vraie URL de test et la signature autorisée. Aucun téléversement sur iPhone.
- Le build web reste vérifié ; il n'offre pas de lecture NFC dans Safari.

Les tests automatisés simulent les lecteurs Android et iOS. Ils ne remplacent pas un essai réel des cartes, de la signature et de la lecture sur l'iPhone.

```sh
flutter analyze
flutter test
npm run check:api
npm run test:api
# Base locale/de test uniquement, après les migrations :
psql <CONNEXION_TEST> -v ON_ERROR_STOP=1 -f test/nfc_database_test.sql -f test/phone_nfc_database_test.sql
```
