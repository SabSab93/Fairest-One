# Tester Fairest-One sur Android — NFC du téléphone et miroir BLE

Branche de développement : `feat/android-ios-phone-nfc`. Le code iOS est conservé ; les réglages de signature Xcode déjà modifiés par l'utilisatrice ne sont pas réinitialisés.

## Parcours pris en charge

1. **Inscription** : dans l'app installée, saisir l'e-mail, toucher CRÉER LA SESSION, puis présenter une NTAG215 au **dos du téléphone Android**, près de son antenne NFC.
2. **Essayage** : depuis le tableau de bord, connecter le miroir BLE et présenter la même carte au **RC522**. Le téléphone relaie les preuves signées et les captures simulées vers Vercel/Supabase.
3. **Récupération** : dans l'app, toucher LIRE LA CARTE, puis présenter la carte au **téléphone Android**. L'écran existant affiche les messages de la session autorisée.

L'antenne NFC n'est pas au même endroit sur tous les Android : elle peut être au centre ou vers le haut du dos. Garder le téléphone déverrouillé et l'application au premier plan. La lecture est unique par demande et peut être annulée en quittant l'écran. Une carte vierge NTAG215 peut être identifiée sans y écrire de données NDEF.

Les captures restent des messages simulés ; aucune caméra n'est ajoutée. L'ESP32 reste en BLE uniquement. Aucun déploiement ou changement de base distante n'est effectué par cette évolution.

## Adaptations du code commun Android / iOS

- `NativePhoneNfcReader` utilise **NfcAAndroid → tag.id** sur Android et **MiFareIos → identifier** sur iOS. Les UID sont convertis dans l'ordre d'origine en hexadécimal majuscule avec les zéros initiaux, comme sur le RC522. Les cartes Android d'une autre famille, notamment NFC-V, sont refusées pour éviter d'inscrire une carte illisible par le miroir.
- La bibliothèque `nfc_manager` 4.2.1 déjà installée suffit : aucune nouvelle dépendance. Elle demande Android **7.0 / API 24 minimum**. La configuration Gradle respecte ce minimum.
- Le manifeste déclare `android.permission.NFC`. La présence de NFC et BLE est optionnelle à l'installation : l'application indique à l'exécution si la fonction manque ou si le NFC est désactivé.
- Les consignes d'approche de carte sont adaptées à Android/iOS ; les messages backend parlent désormais du téléphone.
- `SecurePhoneAccessStore` réutilise `flutter_secure_storage` : trousseau iOS et stockage Android chiffré dont la clé est protégée par Android Keystore. L'identifiant de stockage iOS reste identique, pour conserver les accès déjà créés.
- Les sauvegardes Android de l'app sont désactivées (`allowBackup=false`) pour éviter de restaurer des préférences chiffrées sans leur clé Keystore sur un autre appareil. Les captures restent dans Supabase.
- Pour le BLE, l'app demande via `flutter_blue_plus` l'autorisation de connexion Android avant de lire l'état de l'adaptateur. Le système peut proposer d'activer le Bluetooth. Le plugin gère ensuite les demandes de permission de scan ; aucune seconde bibliothèque de permissions n'est ajoutée.

## Sécurité et backend existants

La récupération utilise **le même téléphone que l'inscription**. L'UID seul ne donne pas accès aux e-mails ni aux captures : l'app conserve un jeton personnel aléatoire dans son stockage sécurisé, dont seul le SHA-256 est lié au client côté serveur. Le jeton n'est ni un secret Supabase ni une clé de miroir et n'est pas écrit sur la carte.

Le passage d'un iPhone à un Android ne transfère pas l'autorisation d'une carte déjà inscrite. Le premier test Android doit utiliser une carte/e-mail encore disponibles dans la **base de test**. Aucun écrasement d'association ou transfert par simple UID n'est ajouté.

Aucun nouvel endpoint ni changement de structure SQL n'est nécessaire pour Android. Réutiliser le backend téléphone déjà préparé :

- `POST /api/clients` : `begin_phone_registration`, `begin_phone_recovery`, `phone_scan`, `phone_cancel`.
- Migrations `supabase-nfc.sql`, puis `supabase-phone-nfc.sql`, après vérification du schéma existant et validation sur une base de test. `supabase-schema.sql` reste réservé à la création initiale de tables inexistantes.
- Le namespace interne historique `native-ios` de ces demandes reste inchangé pour compatibilité ; il est utilisé par le parcours téléphone Android **et** iOS et n'est pas un contrôle du modèle de téléphone.
- Les seules modifications SQL de cette évolution sont les libellés d'erreur, généralisés d'« iPhone » à « téléphone ». Les règles de propriété, d'expiration, d'usage unique et les signatures des captures restent identiques.

L'API de test doit contenir les actions téléphone et ses migrations doivent être en place. Ouvrir l'ancien site Vercel ne suffit pas à installer l'app Android. Ne jamais mettre `SUPABASE_SECRET_KEY`, `ADMIN_PASSWORD` ou `MIRROR_SIGNING_KEY` dans les paramètres de compilation.

## Installer les outils sur le Mac

**Android Studio s'installe sur le Mac**, et Fairest-One sur le téléphone Android. Il n'est pas nécessaire de payer un compte Google Play pour installer et tester localement l'app par USB.

1. Installer [Android Studio](https://developer.android.com/studio), puis terminer son assistant de configuration du SDK Android.
2. Dans **SDK Manager**, installer la plateforme **Android SDK 36** utilisée par le projet, les **SDK Platform-Tools**, les **SDK Build-Tools** nécessaires et **Android SDK Command-line Tools (latest)**. Gradle peut demander des composants supplémentaires comme le NDK ; installer la version indiquée par le message de build.
3. Dans le terminal du projet :

```sh
flutter doctor -v
flutter doctor --android-licenses
flutter pub get
```

Lire et accepter soi-même les licences proposées. Vérifier que la ligne Android toolchain de `flutter doctor` est correcte. Le chemin standard du SDK sur ce Mac est `~/Library/Android/sdk`. Si un autre chemin est utilisé, le renseigner avec `flutter config --android-sdk <CHEMIN_SDK>`.

Le SDK Android n'était pas installé lors de cette intervention : la tentative `flutter build apk --debug` s'est arrêtée avec **No Android SDK found**. Aucun APK Android n'a donc encore été produit ni testé sur téléphone.

## Préparer le téléphone et lancer l'app

1. Utiliser un Android avec NFC, sous **Android 7.0 ou plus récent**. Activer le NFC dans ses paramètres, le Bluetooth et Internet.
2. Activer les **Options pour les développeurs**, puis le **Débogage USB**.
3. Brancher le téléphone au Mac avec un câble de données, le déverrouiller et accepter l'autorisation de débogage du Mac. Sur macOS, aucun pilote USB constructeur n'est normalement nécessaire. [Guide Android officiel](https://developer.android.com/studio/run/device)
4. Dans le dossier du projet :

```sh
flutter devices
flutter run -d <IDENTIFIANT_ANDROID> \
  --dart-define=APP_API_URL=https://VOTRE_API_TEST.vercel.app/api/
```

L'URL doit être celle du backend de **test** réellement configuré, en HTTPS, avec `/api/` à la fin. L'app refusera d'envoyer son jeton personnel à une API HTTP.

Une fois le SDK installé, un APK de test peut également être construit :

```sh
flutter build apk --debug \
  --dart-define=APP_API_URL=https://VOTRE_API_TEST.vercel.app/api/
```

Le fichier attendu après un build réussi est `build/app/outputs/flutter-apk/app-debug.apk`. Le build utilise une signature de développement locale ; il n'est pas destiné à une publication en magasin.

## Test avec les deux cartes

1. Dans Nouvelle session, inscrire A sur le téléphone avec un e-mail inédit et attendre la confirmation. Vérifier `clients`, sa session et le hash d'accès dans Supabase de test.
2. Au tableau de bord, toucher CONNECTER LE MIROIR · ESSAYAGE. Accepter la permission **Appareils à proximité / Bluetooth** et le dialogue d'appairage du miroir avec son PIN. Si Android demande d'activer le Bluetooth, l'accepter, puis relancer la connexion si l'opération a été suspendue.
3. Sur **Android 7 à 11**, le scan BLE nécessite également la permission de localisation et généralement le service de localisation activé. Sur **Android 12+**, les permissions de scan/connexion suffisent ; l'app ne dérive pas la position depuis les scans et déclare `neverForLocation`. Voir [les permissions Android](https://developer.android.com/develop/connectivity/bluetooth/bt-permissions).
4. Présenter A au RC522 : LED verte, deux bips, 3/2/1 et capture simulée. Retirer la carte entre les lectures et enregistrer trois captures.
5. Présenter B non inscrite au RC522 : LED rouge, trois bips, aucun compte à rebours et aucune capture.
6. Dans Récupérer mes photos, scanner A **sur le téléphone Android** : vérifier les trois messages. Relancer l'app et vérifier que l'accès sécurisé est conservé.
7. Vérifier les erreurs : NFC désactivé, absence de carte/timeout, fermeture de l'écran, passage en arrière-plan, Internet coupé, Bluetooth refusé/déconnecté. Aucune fausse confirmation ni capture autorisée sans réponse du backend.

Le firmware doit parler le protocole du dépôt : `firmware/fairest_one/fairest_one.ino`, UUID du service `83de1000-7a28-4b54-9815-47c0ae451001`. Un autre sketch de test avec d'autres UUID ou messages JSON ne sera pas automatiquement compatible. Le guide complet du miroir est [ble-integration.md](ble-integration.md).

## Vérifications et limites

- **45 tests Flutter réussis** : décodage des données natives simulées Android/iOS, ordre des UID, rejet des technologies incompatibles, suppression des doubles notifications, disponibilité/NFC désactivé, annulation/timeouts et écrans d'inscription/récupération sur les deux plateformes.
- **6 tests API réussis** : séparation téléphone/miroir, validation et confidentialité.
- Analyse statique sans anomalie ; compilations iOS Debug sans signature et web release réussies.
- Aucun test de carte physique ou de téléphone Android réalisé par l'agent.
- La compilation APK reste à vérifier dès installation du SDK Android.
- iOS garde sa capacité NFC et ses règles Apple ; le compte Personal Team gratuit ne débloque toujours pas cette capacité. Voir [le guide iOS](iphone-native-nfc.md).

```sh
flutter analyze
flutter test
npm run check:api
npm run test:api
```
