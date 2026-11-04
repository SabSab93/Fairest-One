# Intégration IoT actuelle

L'architecture matérielle utilise **ESP32-C6 ↔ BLE ↔ Flutter iPhone ↔ HTTPS ↔ Vercel/Supabase**.
L’inscription et la récupération lisent la carte directement sur l’iPhone via Core NFC ; voir [iphone-native-nfc.md](iphone-native-nfc.md) pour la configuration et les autorisations. Le RC522, la LED RGB et le buzzer sont pilotés par l'ESP32. Aucun Wi-Fi ESP32 ni Raspberry Pi n'est utilisé. USB sert à programmer et à consulter les logs.

Le protocole, l'audit, les UUID, la migration à faire valider et les instructions de test se trouvent dans [ble-integration.md](ble-integration.md).

`MirrorGatewayClient` et ses tests sont conservés comme ancien contrat HTTP ; aucun service Raspberry Pi correspondant n'existait dans le dépôt. Le parcours matériel utilise désormais `BleMirrorClient` et `NfcFlowController` avec le service HTTP `ApiClient` existant.
