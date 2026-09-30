# Fairest One

Fairest One is a student Master 2 project about IoT and embedded systems for opticians.

The goal is to prepare a connected smart mirror experience: a client tries several frames, the mirror captures each try-on, and the selected photos can later be sent by email.

## Concept

The name refers to:

> Mirror, mirror on the wall, who is the fairest one of all?

The final system is planned as three separated parts. The backend is not
required during the current local prototype phase:

```text
Application Flutter
|
v
Raspberry Pi / API locale
|
v
Arduino / Smart Mirror
|
+-- RC522
+-- OV5640
+-- LEDs
+-- Buzzer
```

The mobile app does not depend on native NFC. RFID/NFC card reading is expected to be handled by the mirror electronics.

The future backend will synchronize clients and sessions between devices,
store photos centrally, send emails, authenticate opticians, and communicate
with the connected mirror. Until those features are needed, client emails are
stored only on the device.

## Current Scope

This first version focuses on a clean Flutter base:

- modern minimal UI inspired by a refined app-cover style;
- responsive dashboard for iPhone and Android tablets;
- new-session flow with email and simulated NFC card association;
- photo-recovery flow prepared for the Raspberry Pi RFID reader;
- persistent local client storage with duplicate prevention;
- PIN-protected administration for clients, photos, and device logs;
- router setup;
- backend configuration placeholder;
- mock mirror status abstraction.

It does not implement real email sending, Supabase synchronization, cloud photo upload, WebSocket events, or Arduino firmware.

## Technologies

- Flutter 3
- Dart
- go_router for navigation
- http for a future backend API client
- shared_preferences for local email storage
- flutter_dotenv for public device and gateway configuration

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

The mobile configuration is stored in `.env`. The committed `.env.example`
documents every available value:

```dotenv
API_BASE_URL=http://raspberrypi.local:8080/
WS_BASE_URL=ws://raspberrypi.local:8080/ws
MIRROR_DEVICE_ID=fairest-one-mirror-01
USE_MOCK_IOT=true
REQUEST_TIMEOUT_SECONDS=10
SUPABASE_URL=https://olktukdervvumtjkjuub.supabase.co
SUPABASE_PUBLISHABLE_KEY=sb_publishable_your_key
USE_SUPABASE=false
```

The `.env` file contains public client configuration only. Never put a password,
private API key, or pairing secret in it because it is bundled into the app.

The Flutter SDK for Supabase is installed. Keep `USE_SUPABASE=false` until
`docs/supabase-schema.sql` has been executed and secure RLS policies have been
defined. The `service_role` key must remain on the Raspberry Pi or backend.

Build-time values can still override the file when needed:

```sh
flutter run --dart-define=API_BASE_URL=http://192.168.1.50:8080/
```

See [docs/iot-architecture.md](docs/iot-architecture.md) for the Raspberry Pi,
Arduino, network, and API plan.

The Supabase tables are defined in
[docs/supabase-schema.sql](docs/supabase-schema.sql). The schema has been
executed on the project; secure RLS policies still need to be added before
enabling Supabase in the application.

## Install Dependencies

```sh
flutter pub get
```

## Run

```sh
flutter run
```

## Verify Environment

```sh
flutter doctor -v
```

## Quality Checks

```sh
flutter analyze
flutter test
```

## Documentation du prototype

Le journal de conception Docusaurus se trouve dans `documentation/`.

```sh
cd documentation
npm install
npm start
```

Le site local est ensuite disponible à l'adresse indiquée par Docusaurus.
Pour vérifier la version de production :

```sh
npm run typecheck
npm run build
```

## Remaining Local Setup

For Android builds, install Android Studio and the Android SDK.

For iOS builds, install the full Xcode application and CocoaPods, then run the first-launch Xcode setup commands shown by `flutter doctor`.
