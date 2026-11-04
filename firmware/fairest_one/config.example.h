#pragma once
// Copy to config.h (ignored by Git). Same ASCII value in Vercel only.
#define MIRROR_SIGNING_KEY "REPLACE_WITH_AT_LEAST_32_RANDOM_ASCII_CHARACTERS"
// Common cathode by default; set true for common anode.
#define RGB_COMMON_ANODE false
// true: active buzzer driven HIGH/LOW; false: passive buzzer via tone().
#define BUZZER_ACTIVE true

// Choose a private six-digit pairing PIN; enter it in the iOS pairing dialog.
#define BLE_PAIRING_PASSKEY 0
