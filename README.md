# Fairest One

Fairest One is a student Master 2 project about IoT and embedded systems for opticians.

The goal is to prepare a connected smart mirror experience: a client tries several frames, the mirror captures each try-on, and the selected photos can later be sent by email.

## Application Expo / EAS

La version mobile React Native est préparée dans [`mobile/`](mobile/README.md), avec inscription/récupération NFC native et miroir BLE pour Android et iOS. Le guide contient les étapes de création des versions EAS de test. Flutter et le backend existants restent disponibles. Aucun déploiement ni changement de base distante n’est automatique.

## Concept

The name refers to:

> Mirror, mirror on the wall, who is the fairest one of all?

The current hardware integration uses the existing Flutter application, Vercel API and Supabase database:

```text
RC522 / RGB LED / buzzer ↔ ESP32-C6 ↔ BLE ↔ Flutter Android / iOS ↔ HTTPS ↔ Vercel ↔ Supabase
```

USB connects the ESP32 to the Mac for programming and logs only. The ESP32 uses no Wi-Fi. Flutter needs Internet to access the existing backend.

Registration and recovery read the card directly on Android and iOS. Start with [the Android testing guide](docs/android-native-nfc.md); see [the native NFC setup guide](docs/iphone-native-nfc.md) for setup, Keychain authorization and the additional migration. Mirror captures continue over BLE.

See [the BLE integration guide](docs/ble-integration.md) for the repository audit, complete protocol, configuration, SQL migration requiring validation, and the exact iPhone/two-card test sequence. The complete Arduino program is in [firmware/fairest_one/fairest_one.ino](firmware/fairest_one/fairest_one.ino). Nothing is automatically deployed or applied to a remote database.

## Current Scope

The existing screens cover registration, recovery and administrator access. The BLE integration adds physical NFC association, backend-verified try-ons, simulated capture messages and session recovery. Real camera uploads and email delivery remain future work.

## Technologies

- Flutter 3
- Dart
- go_router for navigation
- http for the existing Vercel API
- flutter_blue_plus 2.3.14 for iOS BLE
- nfc_manager 4.2.1 for native Android/iOS card reading
- flutter_secure_storage 10.3.1 for personal access stored securely on each phone
- shared_preferences for the simulated NFC card

## Project Structure

```text
lib/
+-- main.dart
+-- app/
|   +-- app.dart
|   +-- router.dart
+-- core/
|   +-- config/
|   +-- network/
|   +-- theme/
+-- features/
    +-- home/
    +-- registration/
    +-- mirror/
```

## Configuration

Use a test Vercel API and Supabase project first. Server-only variables are listed in [.env.example](.env.example). The private hardware signing key belongs only in Vercel and the ignored Arduino `config.h`, never in Flutter.

Run the native iPhone application with the public API URL:

```sh
flutter run -d <IPHONE_ID> --dart-define=APP_API_URL=https://YOUR_PREVIEW.vercel.app/api/
```

Review [docs/supabase-nfc.sql](docs/supabase-nfc.sql) and then [docs/supabase-phone-nfc.sql](docs/supabase-phone-nfc.sql) against the actual test database before applying them. Follow [docs/ble-integration.md](docs/ble-integration.md) for pairing, wiring and validation. The original schema is [docs/supabase-schema.sql](docs/supabase-schema.sql).

## Install Dependencies

```sh
flutter pub get
```

## Run

```sh
flutter run --dart-define=APP_API_URL=https://YOUR_PREVIEW.vercel.app/api/
```

## Verify Environment

```sh
flutter doctor -v
```

## Quality Checks

```sh
flutter analyze
flutter test
npm run check:api
npm run test:api
```

## Documentation du prototype

Le journal de conception et de fabrication est construit avec Docusaurus :

- [Documentation en ligne](https://documentation-theta-eight.vercel.app/)
- [Sources de la documentation](documentation/)

Pour lancer le site localement :

```sh
cd documentation
npm install
npm start
```

Pour vérifier la version de production :

```sh
npm run typecheck
npm run build
```

## Remaining Local Setup

For Android builds, install Android Studio and the Android SDK.

For iOS builds, install the full Xcode application and CocoaPods, then run the first-launch Xcode setup commands shown by `flutter doctor`.
