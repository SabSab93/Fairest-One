# Mise en production sans Raspberry Pi

Cette première production utilise trois éléments séparés :

~~~text
Flutter Web -> API Vercel -> Supabase
Docusaurus  -> projet Vercel séparé
Raspberry Pi / Arduino -> mode simulé pour le moment
~~~

## Pourquoi les e-mails n'apparaissaient pas

La configuration locale utilisait **USE_SUPABASE=false**. Les clients étaient
donc enregistrés par shared_preferences dans le navigateur ou l'appareil, pas
dans la table Supabase.

Activer seulement **USE_SUPABASE=true** ne suffit pas : le RLS est activé et
aucune policy publique n'autorise l'accès. La production passe donc par une API
Vercel, qui conserve la clé secrète côté serveur.

## 1. Sécuriser les tables

Exécuter [supabase-production.sql](supabase-production.sql) dans le SQL Editor
Supabase. Le script retire les droits directs des rôles anon et authenticated.
L'API serveur utilise le rôle privilégié.

## 2. Créer un second projet Vercel

Le projet Docusaurus reste déployé séparément. Pour l'application :

1. Importer à nouveau le dépôt **SabSab93/Fairest-One** dans Vercel.
2. Nommer le projet, par exemple **fairest-one-app**.
3. Laisser **Root Directory** vide : l'application est à la racine du dépôt.
4. Choisir **Framework Preset: Other**.
5. Le fichier vercel.json fournit la commande et le dossier de sortie.

Réglages attendus :

~~~text
Build Command: npm run build
Output Directory: build/web
Install Command: npm install
~~~

Le premier build télécharge Flutter 3.47.5. Il sera donc plus long que les
suivants.

## 3. Ajouter les variables Vercel

Dans **Settings > Environment Variables**, ajouter pour Production, Preview et
Development :

~~~text
SUPABASE_URL=https://olktukdervvumtjkjuub.supabase.co
SUPABASE_SECRET_KEY=sb_secret_...
ADMIN_PASSWORD_HASH=empreinte_sha256_du_mot_de_passe
USE_MOCK_IOT=true
FLUTTER_VERSION=3.47.5
~~~

La Secret key se trouve dans Supabase, dans les réglages des API keys. Ne jamais
l'ajouter à .env, Flutter, GitHub ou une capture d'écran.

Pour générer l'empreinte du mot de passe administrateur :

~~~sh
printf %s "votre-mot-de-passe" | shasum -a 256
~~~

## 4. Déployer et vérifier

Après le déploiement :

1. ouvrir l'application Vercel ;
2. créer une nouvelle session et simuler une carte ;
3. vérifier la nouvelle ligne dans **Supabase > Table Editor > clients** ;
4. ouvrir l'administration et vérifier que le client apparaît ;
5. tester la récupération des photos avec la carte simulée.

Un appel direct à **/api/clients** sans mot de passe doit répondre avec un statut
401. C'est le comportement attendu.

## Limites actuelles

- Ce déploiement est une préproduction de démonstration. Ne pas encore utiliser
  de véritables adresses de clients en magasin.
- Le lecteur NFC, la caméra et les commandes du miroir restent simulés.
- Les photos et leur envoi par e-mail ne sont pas encore implémentés.
- Le mot de passe administrateur du prototype doit être remplacé avant une
  utilisation réelle avec des données clients.
- Lorsque la Raspberry Pi sera disponible, elle pourra utiliser l'API serveur
  ou remplacer certaines opérations de simulation.
