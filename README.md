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

It does not implement real email sending, cloud photo upload, hardware events,
or Arduino firmware.

## Technologies

- Flutter 3
- Dart
- go_router for navigation
- http for the Vercel API and future Raspberry Pi gateway
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

L'application Flutter appelle toujours l'API Vercel, qui accède à Supabase.
Seules trois variables serveur sont nécessaires dans Vercel (Production) :

```dotenv
SUPABASE_URL=https://olktukdervvumtjkjuub.supabase.co
SUPABASE_SECRET_KEY=sb_secret_a_remplacer
ADMIN_PASSWORD=iou
```

Le fichier `.env` reste ignoré par Git. Quand l'API de la Raspberry Pi sera
connue, son adresse sera fournie au build Flutter :

```sh
flutter run --dart-define=MIRROR_API_URL=http://raspberrypi.local:8080/
```

See [docs/iot-architecture.md](docs/iot-architecture.md) for the Raspberry Pi,
Arduino, network, and API plan.

The Supabase tables are defined in
[docs/supabase-schema.sql](docs/supabase-schema.sql). Flutter never receives
the Supabase secret: only the Vercel API accesses the database.

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
