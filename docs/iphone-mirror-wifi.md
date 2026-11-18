# Tester le miroir en Wi-Fi sur iPhone

1. Activez le partage de connexion sur l’iPhone et choisissez **Maximiser la compatibilité**.
2. Téléversez `firmware/fairest_one/fairest_one.ino` sur l’**ESP32S3 Dev Module** avec **16 MB Flash**, **OPI PSRAM** et la partition **16M Flash (2MB APP/12.5MB FATFS)**. Pour le port USB‑UART, utilisez **USB CDC On Boot → Disabled**. Conservez le `config.h` local avec la clé de signature actuelle.
3. Ouvrez le moniteur série à **115200 bauds**, avec **New Line**. Au démarrage, saisissez le nom du partage puis le mot de passe lorsqu’ils sont demandés. Ils sont utilisés en mémoire vive. Le miroir affiche ensuite son adresse IP.
4. Installez le build iOS Release et ouvrez Fairest One. Dans **Adresse Wi-Fi du miroir**, saisissez l’adresse du moniteur si elle diffère de la valeur proposée. Autorisez le réseau local si iOS le demande.
5. Testez **Nouveau client**, **Essayer mes lunettes** puis **Récupérer ma session**. Gardez le partage actif. L’iPhone utilise Internet pour joindre Vercel et le réseau local pour communiquer avec le miroir.
6. Récupérez la session avec le badge utilisé pour l’essayage. Touchez une miniature pour l’agrandir. Sélectionnez une ou plusieurs photos, ou toutes les photos, puis ouvrez l’e-mail prérempli avec les JPEG en pièces jointes. Configurez un compte dans Mail sur l’iPhone pour effectuer l’envoi.

Le firmware utilise HTTP sur le réseau privé du prototype et HTTPS pour transmettre à l’API les JPEG signés. Appliquez la migration [Supabase des photos](supabase-mirror-photos.sql) avant de mettre en production cette API. Les fichiers sont privés et l’API accorde des liens temporaires après lecture autorisée du badge. Une fois l’API déployée, installez le nouveau build iPhone et téléversez le programme S3. Pour vérifier l’image et l’e-mail, faites un nouvel essayage avec la caméra. Les anciennes captures simulées sont exclues de la galerie.
