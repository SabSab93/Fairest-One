# Préparation IoT

## Architecture cible

```text
iPhone / tablette Samsung
        |
        | Wi-Fi : HTTP + WebSocket
        v
Raspberry Pi : passerelle locale
        |
        | USB série : 115200 bauds
        v
Arduino : capteurs, LED, buzzer et commandes matérielles
```

Le projet `pwa-led` est une bonne référence pour le modèle de commandes simples
(`ON`, `OFF`) et l'affichage de l'état. Son Web Bluetooth direct est remplacé ici
par une API sur la Raspberry Pi, afin de fonctionner de la même manière sur iOS
et Android.

## Parcours client

```text
Nouvelle session
  -> email + UID de carte
  -> essayage et photos au miroir
  -> retour à la borne
  -> lecture de la même carte
  -> sélection puis envoi des photos
```

La carte NFC conserve uniquement son UID matériel. L'email, les sessions et les
photos restent dans le stockage local pendant le prototype, puis dans Supabase.
L'UID sert seulement de clé de recherche et aucune donnée personnelle n'est
écrite sur la carte.

Le schéma proposé se trouve dans `docs/supabase-schema.sql` avec les tables
`clients`, `sessions`, `photos` et `device_logs`. Les images seront placées dans
Supabase Storage ; la table `photos` ne conservera que leur chemin et leurs
métadonnées.

## Configuration Flutter

Le fichier `.env` contient uniquement de la configuration publique :

| Variable | Valeur de départ | Rôle |
| --- | --- | --- |
| `API_BASE_URL` | `http://raspberrypi.local:8080/` | Adresse HTTP de la Raspberry Pi |
| `WS_BASE_URL` | `ws://raspberrypi.local:8080/ws` | Événements temps réel du miroir |
| `MIRROR_DEVICE_ID` | `fairest-one-mirror-01` | Identifiant du miroir |
| `USE_MOCK_IOT` | `true` | Utilise le miroir simulé tant que le matériel est absent |
| `REQUEST_TIMEOUT_SECONDS` | `10` | Délai maximal d'une requête locale |

Si `raspberrypi.local` ne fonctionne pas sur le réseau, remplacer ce nom par
l'adresse IP locale de la Raspberry Pi, par exemple `192.168.1.50`.

Passer `USE_MOCK_IOT=false` seulement lorsque la passerelle Raspberry répond à
l'API prévue.

## Contrat API proposé

```text
GET  /api/v1/health
GET  /api/v1/mirror/status
POST /api/v1/mirror/commands
WS   /ws
```

Exemple de commande envoyée par l'application :

```json
{
  "deviceId": "fairest-one-mirror-01",
  "command": "led_on"
}
```

Les premières commandes préparées dans Flutter sont `led_on`, `led_off` et
`start_capture`.

## Configuration future de la Raspberry Pi

Le service installé sur la Raspberry devra avoir son propre `.env`, non partagé
avec l'application mobile :

```dotenv
GATEWAY_HOST=0.0.0.0
GATEWAY_PORT=8080
DEVICE_ID=fairest-one-mirror-01
ARDUINO_SERIAL_PORT=/dev/ttyACM0
ARDUINO_BAUD_RATE=115200
PAIRING_SECRET=valeur-longue-et-aleatoire
```

`PAIRING_SECRET` reste uniquement sur la Raspberry ou sur un serveur sécurisé.
Il ne doit jamais être ajouté au `.env` Flutter, car les ressources d'une
application mobile peuvent être extraites.

## Mise en service

1. Connecter l'Arduino à la Raspberry Pi en USB.
2. Vérifier son port avec `ls /dev/ttyACM*` ou `ls /dev/ttyUSB*`.
3. Lancer la passerelle sur le port `8080`.
4. Mettre le téléphone ou la tablette sur le même réseau Wi-Fi.
5. Vérifier `GET /api/v1/health` depuis l'appareil mobile.
6. Remplacer `USE_MOCK_IOT=true` par `false`.

Pour une version de production, utiliser HTTPS/WSS et un mécanisme d'association
du miroir. Le HTTP local autorisé actuellement sert uniquement au prototype.
