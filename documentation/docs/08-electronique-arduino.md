---
title: Électronique et Arduino
sidebar_position: 9
description: Câblage, logique embarquée et code du prototype.
---

# Électronique et Arduino

Le parcours matériel actuel utilise un **ESP32-C6**, un RC522, une LED RGB et un buzzer. L'iPhone communique en **BLE** avec le miroir et relaie les opérations vers l'API Vercel / Supabase. Le Wi-Fi de l'ESP32 et la Raspberry Pi ne sont pas utilisés. Les anciennes pistes ESP32-S3-CAM / ESP32-C3 restent des idées d'évolution.

## Affectation des broches

| Élément | GPIO |
|---|---:|
| LED rouge / verte / bleue | 5 / 6 / 4 |
| Buzzer | 20 |
| RC522 SS / RST | 10 / 3 |
| SPI SCK / MOSI / MISO | 19 / 18 / 2 |

Vérifier les couleurs réelles au test RGB de démarrage et la polarité de la LED. RC522 alimenté en 3,3 V, masse commune. Le câblage physique reste à tester.

## Code Arduino complet

Le programme versionné est `firmware/fairest_one/fairest_one.ino` à la racine du dépôt. Copier `config.example.h` vers `config.h` et renseigner les valeurs privées avant téléversement. Ne jamais publier ce fichier privé.

Le guide complet est `docs/ble-integration.md` : audit, UUID du service BLE, protocole JSON fragmenté, configuration iPhone, migration Supabase à valider et tests avec deux cartes.

## Fonctionnement

Flutter obtient un défi temporaire du backend et arme le lecteur par BLE. Le RC522 lit l'UID ; le firmware signe cette lecture et la transmet à Flutter. Le backend décide de l'association, de la reconnaissance ou de la récupération.

Pour un essayage reconnu, Flutter autorise la capture : LED verte, deux bips, compte à rebours 3/2/1 et événement de capture simulée. Flutter enregistre le message côté backend. Une carte inconnue entraîne LED rouge et trois bips, sans capture. Déconnexion, annulation ou absence de réponse arrêtent l'opération. Retirer la carte entre deux lectures.

Compilation logicielle et tests automatisés ne remplacent pas les essais du montage réel ; aucun flashage automatique n'est effectué.
