# Fairest-One : ESP32-C6 ↔ iPhone en BLE

Branche : `feat/esp32-c6-nfc-integration`. Aucun déploiement, flashage ni changement de Supabase distant n'est effectué par ces fichiers.

## Audit du dépôt avant modification

| Point demandé | Implémentation constatée |
|---|---|
| Inscription | `registration_screen.dart` valide l'e-mail, génère une carte de démonstration, puis appelle `ClientStore.createClient`. `RemoteClientStore` utilise `ApiClient` pour `POST /api/clients`. |
| E-mails | L'API normalise l'e-mail en minuscules, puis l'insère dans `clients.email` (unique). La clé Supabase reste dans les variables serveur. Le schéma SQL est une proposition locale ; le schéma réel distant n'a pas été inspecté. |
| Simulation NFC | UID `DEMO-<horodatage hexadécimal>` ; `DemoCardStore` conserve le dernier UID via SharedPreferences. Aucun accès NFC matériel depuis l'iPhone. |
| Association | `clients.card_uid`, unique et non nul, contient l'UID normalisé. Aucun e-mail écrit sur la carte. |
| Sessions | Tables `sessions(client_id,status,started_at,ended_at)` définies. Aucun code de création ou de clôture de session dans l'API initiale. Le bouton « CRÉER LA SESSION » créait uniquement le client. |
| Récupération | Relit le dernier UID simulé, appelle `findByCardUid`, affiche l'e-mail et un compteur. Pas de chargement de photos/messages ni de sélection/envoi implémentés. |
| API | Un seul fichier : `api/clients.mjs`. `GET` liste admin via `X-Admin-Password`, `GET ?card_uid=…` recherche, `POST` inscrit, `OPTIONS`. La recherche UID était publique et exposait l'e-mail. |
| Firmware | Aucun `.ino`, firmware ou configuration PlatformIO versionné. `documentation/docs/08-electronique-arduino.md` contenait uniquement un emplacement vide. Aucun programme matériel existant n'a donc pu être conservé ou vérifié. |
| Réutilisable | Écrans, navigation GoRouter, thème, `ClientRecord`, `ClientStore`, `ApiClient`, endpoint Vercel et tables `clients`, `sessions`, `photos`, `device_logs`. `MirrorGatewayClient` garde ses anciennes commandes HTTP mais n'est pas utilisé par le BLE. |

## Architecture livrée

```text
RC522 / LED / buzzer ↔ ESP32-C6 (serveur GATT)
                               ↕ BLE
                          Flutter iPhone (client GATT)
                               ↕ HTTPS /api/clients
                         API Vercel ↔ Supabase
```

L'ESP32 n'utilise aucun Wi-Fi et n'effectue aucune requête HTTP. L'iPhone doit avoir Internet (cellulaire ou Wi-Fi) pour joindre Vercel. L'application reste ouverte au premier plan pendant l'essayage. USB sert au téléversement du firmware et aux logs.

Les écrans et le design sont conservés. Un bouton BLE dans le tableau de bord arme les essayages successifs. L'inscription et la récupération établissent également la connexion au besoin. Quitter le parcours ou passer en arrière-plan annule la lecture ; relancer explicitement au retour. Une déconnexion annule le compte à rebours ; aucune reconnexion ne relance automatiquement une capture.

`USE_MOCK_IOT` vaut désormais `false` par défaut. Le code de simulation et les tests existants sont conservés. Les anciennes opérations distantes par UID et l'inscription directe demandent désormais `X-Admin-Password` : la simulation historique n'autorise plus l'accès public à Supabase. Ne jamais intégrer ce mot de passe dans les paramètres de compilation Flutter. Pour la simulation automatisée, injecter un `ClientStore` factice, comme dans `widget_test.dart`.

## Fichiers Flutter

- Ajout : `lib/features/mirror/data/ble_mirror_client.dart` (transport GATT et JSON), `nfc_flow_controller.dart` (coordination BLE / HTTP).
- Adaptation : `registration_screen.dart`, `photo_recovery_screen.dart`, `home_screen.dart` et le texte du journal `admin_screen.dart`.
- Enrichissement de `ClientRecord` avec une liste de messages ; configuration du mode réel dans `AppConfig`.
- `ApiClient`, `ClientStore`, le thème, GoRouter et les anciennes commandes `MirrorGatewayClient` sont réutilisés/conservés.
- Dépendance `flutter_blue_plus` figée dans `pubspec.yaml`/`pubspec.lock`, permission iOS et déclarations BLE Android. La validation matérielle de cette livraison cible iOS ; Android n'a pas été testé.

## Protocole BLE v1

Nom annoncé : `Fairest-One-C6`. Un seul miroir / iPhone à la fois pour ce prototype.

| Élément | UUID | Propriété |
|---|---|---|
| Service Fairest-One | `83de1000-7a28-4b54-9815-47c0ae451001` | Service GATT |
| Événements ESP32 → Flutter | `83de1001-7a28-4b54-9815-47c0ae451001` | NOTIFY |
| Commandes Flutter → ESP32 | `83de1002-7a28-4b54-9815-47c0ae451001` | WRITE avec réponse |

Transport : UTF-8, un objet JSON par ligne terminée par `\n`. Les deux côtés fragmentent en paquets de **20 octets maximum** et réassemblent avant de décoder. Aucune hypothèse sur le MTU iOS. Taille maximale : 511 octets par commande, 1024 par événement. Les écritures Flutter sont sérialisées pour éviter le mélange de commandes lors d'une annulation. Les événements sont corrélés par `token`, jamais uniquement par UID.

1. Flutter appelle `begin_registration`, `begin_recognition` ou `begin_recovery`. Le serveur renvoie un défi aléatoire de 256 bits valable **90 secondes**. Seul son SHA-256 est stocké.
2. Flutter s'abonne aux notifications, puis écrit :

```json
{"type":"scan","token":"<64 caractères hexadécimaux>"}
```

3. Le firmware attend une carte physique, puis notifie :

```json
{"type":"card_scanned","token":"<défi>","uid":"A1B2C3D4","proof":"<HMAC hexadécimal>"}
```

La preuve est `HMAC-SHA256(MIRROR_SIGNING_KEY, token + "|" + UID_MAJUSCULE + "|scan")`. La clé est une chaîne ASCII privée, identique dans Vercel et `config.h`, jamais dans Flutter. Flutter relaie `action: scan`, `token`, `card_uid`, `proof` au backend. Une preuve d'un autre défi ou d'un autre UID est refusée.

4. Après la réponse backend, Flutter écrit :

```json
{"type":"card_result","token":"<défi>","recognized":true,"capture":true}
```

`capture:true` est réservé à l'essayage reconnu. Pour association/récupération réussie : `recognized:true,capture:false`. Carte inconnue : `recognized:false,capture:false`. Sans confirmation valide et corrélée, aucune capture. Une erreur backend provoque une annulation, jamais un feu vert.

5. Pour l'essayage reconnu : LED verte, deux bips, compte à rebours série 3/2/1 puis :

```json
{"type":"capture_simulated","token":"<défi>","uid":"A1B2C3D4","proof":"<HMAC hexadécimal>"}
```

La preuve utilise cette fois le suffixe `|capture`. Flutter relaie `action:capture` au backend. Celui-ci vérifie la preuve, la carte, l'expiration et l'autorisation de capture créée lors de la reconnaissance. Une relance du même enregistrement ne crée pas de doublon. Flutter confirme ensuite : `{"type":"capture_saved","token":"<défi>"}`.

Autres messages : `{"type":"cancel","token":"<défi>"}` et événement `{"type":"error","token":"<défi>","code":"flutter_timeout"}`. Champs inconnus ignorés, messages invalides ignorés jusqu'au timeout. Un événement tardif d'une autre opération ne déclenche rien.

Timeouts firmware : lecture 35 s ; attente de réponse Flutter après scan 12 s ; attente de confirmation d'enregistrement 25 s. Flutter : événement 35 s, requête HTTP 10 s. Retirer la carte au moins 600 ms entre deux lectures. Une carte maintenue sur le lecteur ne génère pas de captures répétées.

## API existante étendue

Toutes les opérations utilisent **POST `/api/clients`** avec `action` dans le JSON ; aucun second endpoint équivalent.

| Action | Entrée | Résultat |
|---|---|---|
| `begin_registration` | `email` | `pending`, `token`, `expires_in` |
| `begin_recognition` / `begin_recovery` | — | Défi temporaire |
| `scan` | `token`, `card_uid`, `proof` | `associated`, `recognized`, `recovered`, `unknown`, ou `failed` avec code de doublon |
| `capture` | `token`, `card_uid`, preuve `capture` | `captured`, idempotent |
| `cancel` | `token` | `cancelled` |

La récupération renvoie `session_id` et un `client` au format existant, enrichi de `messages`. Elle consomme le défi : le même scan ne peut pas relire les e-mails/messages. Une réponse de récupération perdue nécessite une nouvelle présentation de carte. Une inscription dont la réponse a été perdue peut déjà être enregistrée : vérifier avant de recommencer ; les contraintes uniques évitent les doublons.

Les opérations publiques par UID seul sont refusées (`401`). Les opérations administrateur restent accessibles avec leur mot de passe saisi par l'opérateur. La preuve matérielle assure l'origine de la lecture ; elle ne rend pas l'UID inviolable : une carte clonée reste possible. Le firmware impose un appairage BLE avec PIN privé et chiffrement/authentification. Le PIN doit être saisi sur l'iPhone à la première connexion. La vérification de ce dialogue réel reste à faire sur le matériel.

Ce prototype borne à 20 les défis simultanés pour un miroir ; il ne fournit pas d'authentification de compte client ni de protection anti-abus complète pour un déploiement public. L'autorisation de déploiement et la politique d'accès du lieu sont à revoir avant une ouverture publique.

## SQL à faire valider, puis appliquer sur un projet de test

Fichier : [`supabase-nfc.sql`](supabase-nfc.sql).

- Ajout nullable de `photos.message` ; aucune photo existante supprimée.
- Table `nfc_requests` pour les défis expirables et leur état ; RLS activée, aucun accès `anon`/`authenticated`.
- Fonction transactionnelle `nfc_operation`, exécutable uniquement par `service_role`. L'API vérifie les HMAC avant l'appel.
- Réutilisation de `clients` et `sessions` ; inscription réussie = création du client et d'une session active. Les essayages réutilisent sa dernière session active. La récupération lit sa dernière session. La clôture de session n'est pas ajoutée.
- Les captures occupent `photos` avec `storage_path = simulated/<id-demande>`, un message et un horodatage. Ce chemin est un marqueur, pas un objet Supabase Storage.

Avant application, comparer le schéma Supabase réel à `supabase-schema.sql` : colonnes, contraintes et relations. Ne pas réexécuter le schéma de création sur une base existante. Vérifier également les restrictions de `supabase-production.sql` pour les tables existantes. Ne pas donner l'accès direct aux tables à l'application.

Variables **serveur Vercel de test** :

```dotenv
SUPABASE_URL=https://VOTRE_PROJET_TEST.supabase.co
SUPABASE_SECRET_KEY=<secret serveur du projet de test>
ADMIN_PASSWORD=<mot de passe administrateur distinct>
MIRROR_DEVICE_ID=fairest-one-c6-01
MIRROR_SIGNING_KEY=<chaîne ASCII aléatoire privée de 64 caractères>
```

Génération possible de la clé : `openssl rand -hex 32`. Copier la valeur dans la configuration privée du firmware et les variables Vercel ; elle n'est jamais un `--dart-define`. Utiliser une API Preview et un projet Supabase de test. Le téléphone doit pouvoir accéder à cette Preview ; la protection Vercel éventuelle doit être configurée pour le test, sans intégrer de secret de contournement dans l'app.

Les demandes expirées ne peuvent plus être utilisées. Leur purge est une opération de maintenance à planifier, par exemple suppression des lignes `nfc_requests` âgées de plus de 7 jours après validation ; les captures sont indépendantes et conservées.

## Firmware et câblage

Programme complet : [`../firmware/fairest_one/fairest_one.ino`](../firmware/fairest_one/fairest_one.ino).

| Composant | GPIO |
|---|---:|
| LED rouge | 5 |
| LED verte | 6 |
| LED bleue | 4 |
| Buzzer | 20 |
| RC522 SS / SDA (SPI, pas I²C) | 10 |
| RC522 RST | 3 |
| RC522 SCK | 19 |
| RC522 MOSI | 18 |
| RC522 MISO | 2 |

Alimenter le RC522 en 3,3 V, masse commune. Conserver les résistances adaptées aux LED. Le programme allume successivement les sorties déclarées rouge, verte et bleue au démarrage ; vérifier les couleurs réelles et corriger les `#define` si nécessaire. `RGB_COMMON_ANODE` règle la polarité et `BUZZER_ACTIVE` distingue buzzer actif/passif. Aucun code original n'étant présent, leur comportement réel reste à comparer à ton montage.

Sur la puce ESP32-C6, l'USB Serial/JTAG natif utilise **GPIO12/13**, selon [Espressif](https://docs.espressif.com/projects/esp-idf/en/latest/esp32c6/get-started/establish-serial-connection.html). Les GPIO18/19 demandés sont conservés ; vérifier le schéma de la carte exacte et son connecteur USB avant de conclure à un conflit. Le câblage physique n'a pas été inspecté.

Installation Arduino IDE :

1. Gestionnaire de cartes : **esp32 by Espressif Systems 3.3.12**. Choisir **ESP32C6 Dev Module** (ou la référence exacte de la carte).
2. Bibliothèques : **MFRC522 1.4.12**, **ArduinoJson 7.4.2**. BLE et mbedTLS proviennent du cœur ESP32 ; aucune bibliothèque Wi-Fi ajoutée.
3. Copier `config.example.h` vers `config.h` dans le dossier du sketch. Renseigner `MIRROR_SIGNING_KEY`, choisir un `BLE_PAIRING_PASSKEY` privé de six chiffres, régler LED/buzzer. `config.h` est ignoré par Git.
4. Ouvrir le `.ino`, compiler, puis téléverser manuellement via USB. Ouvrir le moniteur série à **115200 bauds**. Selon la carte, activer « USB CDC On Boot » pour voir les logs sur l'USB natif.
5. Vérifier le test RGB, la version RC522 et le message BLE prêt. Aucune connexion Wi-Fi n'est attendue.

## Configuration exacte de l'iPhone

1. Installer Xcode complet et terminer son initialisation ; les seuls Command Line Tools ne permettent pas de construire/signer iOS. Ouvrir `ios/Runner.xcworkspace` et choisir l'équipe de signature pour Runner si nécessaire. Installer les outils iOS demandés par `flutter doctor`.
2. Depuis la racine : `flutter pub get`, puis `flutter devices` avec l'iPhone connecté au Mac, déverrouillé et approuvé. Activer le mode développeur iOS si demandé.
3. Après validation et mise à disposition **manuelle** de l'API de test, lancer :

```sh
flutter run -d <IDENTIFIANT_IPHONE> \
  --dart-define=APP_API_URL=https://VOTRE_PREVIEW.vercel.app/api/
```

Le `/api/` final est nécessaire. Aucun secret Supabase/miroir dans cette commande.

4. Autoriser le Bluetooth à la demande. La clé `NSBluetoothAlwaysUsageDescription` est ajoutée dans `ios/Runner/Info.plist`. En cas de refus : Réglages → Confidentialité et sécurité → Bluetooth → Fairest One. Réactiver le Bluetooth si nécessaire.
5. Le scan et la connexion se font **dans l'application**. Accepter le dialogue d'appairage iOS et saisir le PIN privé configuré dans le firmware. En cas de changement du PIN ou des liens d'appairage, oublier le périphérique côté iPhone si disponible et réinitialiser les liens côté ESP32 selon les outils Arduino.
6. Garder l'application au premier plan et Internet actif. Le BLE ne se teste pas dans Safari sur iPhone : utiliser l'application iOS native. Les anciens écrans web restent construisibles, mais ce parcours matériel cible iOS natif.

`flutter_blue_plus` **2.3.14** a été résolu avec le SDK du dépôt et sa cible iOS **15.0**. Le [paquet et sa licence](https://pub.dev/packages/flutter_blue_plus) couvrent l'usage éducatif de ce projet (`License.nonprofit`) ; une utilisation commerciale nécessite la licence correspondante. Le programme utilise le cœur Arduino 3.3.12 déjà installé, dont les exemples BLE documentent l'appairage sécurisé.

## Test manuel avec les cartes A et B

1. **Association A** : Nouvelle session → e-mail de test inédit → CRÉER LA SESSION (ou icône NFC). Attendre « Présentez la carte », présenter A. Attendre la confirmation. Vérifier une ligne `clients` et une session liée dans Supabase de test.
2. **Reconnaissance A** : retirer A, revenir au tableau de bord, toucher CONNECTER LE MIROIR · ESSAYAGE, attendre le message de présentation, puis approcher A. Vérifier LED verte, deux bips et logs 3/2/1. Attendre « Capture simulée enregistrée » avant de poursuivre.
3. **Refus B** : retirer A, attendre la prochaine lecture, présenter B non inscrite. Vérifier LED rouge, trois bips, aucun compte à rebours et aucune ligne `photos` supplémentaire.
4. **Trois captures** : retirer puis présenter A encore deux fois, en attendant à chaque fois le réarmement. Laisser A sur le lecteur : aucune capture supplémentaire ne doit apparaître.
5. **Récupération** : retirer A, ouvrir Récupérer mes photos → LIRE LA CARTE → présenter A. Vérifier les trois messages « Photo simulée n°1/2/3 — Essayage effectué. » dans le même écran.
6. **Données** : sur le projet de test, joindre `clients → sessions → photos`. Vérifier les trois messages et les chemins `simulated/…`, l'absence de capture pour B et les états des demandes NFC. Aucun message ni e-mail n'est écrit sur les cartes.
7. **Erreurs** : couper Internet avant confirmation : aucune capture autorisée ; arrêter/rebrancher le BLE pendant le compte à rebours : opération annulée ; attendre sans carte : timeout ; refuser Bluetooth : message explicite ; relancer après rétablissement. Couper Internet après l'événement de capture : le backend peut avoir enregistré avant la perte de réponse ; contrôler Supabase avant une nouvelle tentative. Les relances du même événement sont idempotentes.

## Vérifications effectuées et limites

- Tests API Node : protection des anciennes routes, création de défi, HMAC, altération UID, séparation scan/capture, expiration et erreurs backend.
- Tests Flutter : transport JSON fragmenté, association/reconnaissance/refus/récupération avec faux BLE, relance d'enregistrement, échec backend, déconnexion, timeout, annulation et tests des écrans existants.
- Migration et scénarios réels PostgreSQL sur une **base locale jetable**, sans accès à Supabase distant. Les fixtures sont annulées par rollback.
- Compilation Arduino pour `esp32:esp32:esp32c6`, cœur 3.3.12, sans téléversement : 768 660 octets de programme (58 %), 19 504 octets de variables globales (5 %).
- `flutter analyze` sans anomalie, 22 tests Flutter et 4 tests API réussis ; build web release réussi.
- Le build/signature iOS, le dialogue d'appairage, les signaux électriques et les deux cartes physiques restent à valider sur le Mac/iPhone/montage. Xcode complet n'est pas sélectionné dans cet environnement.

Commandes :

```sh
flutter analyze
flutter test
flutter test --dart-define=USE_MOCK_IOT=true
npm run check:api
npm run test:api
# Uniquement sur une base locale/de test avec les schémas appliqués :
psql <CONNEXION_BASE_TEST> -v ON_ERROR_STOP=1 -f test/nfc_database_test.sql
```
