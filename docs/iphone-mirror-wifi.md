# Tester le miroir en Wi-Fi sur iPhone

1. Activez le partage de connexion sur l’iPhone et choisissez **Maximiser la compatibilité**.
2. Téléversez `firmware/fairest_one/fairest_one.ino` avec la carte **ESP32C6 Dev Module** et **USB CDC On Boot → Enabled**. Conservez le `config.h` local avec la clé de signature actuelle.
3. Ouvrez le moniteur série à **115200 bauds**, avec **New Line**. Au démarrage, saisissez le nom du partage puis le mot de passe lorsqu’ils sont demandés. Ils sont utilisés en mémoire vive. Le miroir affiche ensuite son adresse IP.
4. Installez le build iOS Release et ouvrez Fairest One. Dans **Adresse Wi-Fi du miroir**, saisissez l’adresse du moniteur si elle diffère de la valeur proposée. Autorisez le réseau local si iOS le demande.
5. Testez **Nouveau client**, **Essayer mes lunettes** puis **Récupérer ma session**. Gardez le partage actif. L’iPhone utilise Internet pour joindre Vercel et le réseau local pour communiquer avec le miroir.

Le firmware utilise HTTP sur le réseau privé du prototype. L’API continue de vérifier les preuves signées par l’ESP32. Le transport Bluetooth de l’app Android nécessite un firmware Bluetooth compatible, comme celui du commit `9c482ac`. Pour le premier contrôle de connectivité sans lecteur de carte, utilisez `firmware/test_wifi_iphone`.
