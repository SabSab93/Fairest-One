---
title: Relevés dimensionnels
sidebar_position: 4
description: Méthode utilisée pour collecter et vérifier les dimensions des composants.
---

# Relevés dimensionnels

Cette étape rassemble les dimensions utilisées pour construire les logements, passages de câbles et fixations dans Fusion 360.

## Méthode de relevé

Après validation de la nomenclature et commande des composants par notre professeur, les dimensions ont été relevées dans les fiches fournisseurs ou recherchées à partir des références. Certaines références correspondant à plusieurs formats, notamment pour la carte caméra, nous avons retenu le format le plus standard dans l'attente d'une vérification physique.

La première modélisation Fusion 360 utilise les dimensions nominales, sans marge ajoutée. Cura ne définissant pas automatiquement le jeu nécessaire à l'assemblage, les composants seront mesurés à leur réception, puis une impression test permettra d'ajuster les dimensions si nécessaire.

## Fiches des composants

| Composant | Dimensions relevées | Photo constructeur | Source |
|---|---|---|---|
| Miroir rectangulaire | 16 × 12 cm | Photo à ajouter | Mesure communiquée par l'équipe |
| ESP32-S3-CAM N16R8 + OV5640 | Carte : 28 × 57 mm ; caméra : 30 ± 0,20 × 8,5 ± 0,2 mm ; connexion : 5,6 mm | Voir ci-dessous | Relevés fournisseur |
| RFID-RC522 | Module : 60 × 40 mm ; carte NFC : 85 × 54 mm | Voir ci-dessous | Données fournisseur vérifiées sur les éléments reçus |
| LED RGB 5 mm | Boîtier : 4,8 × 5,5 mm ; pattes : 25 à 28 mm | Voir ci-dessous | Relevé fournisseur |
| Buzzer passif | À renseigner | Photo à ajouter | Lien constructeur à ajouter |
| PMMA transparent | À renseigner | Photo à ajouter | Source à ajouter |
| Inserts et vis M3 | À renseigner | Photo à ajouter | Source à ajouter |

### Carte ESP32-S3-CAM N16R8

La carte mesure 28 mm de largeur et 57 mm de longueur d'après le relevé dimensionnel du vendeur. Ces valeurs seront vérifiées sur le composant avant la conception définitive de son logement.

![Dimensions de la carte ESP32-S3-CAM N16R8 : 28 mm de largeur et 57 mm de longueur](/img/components/esp32-s3-cam-dimensions.png)

### Module caméra OV5640

L'OV5640 est la caméra du dispositif. Elle est reliée à la carte ESP32-S3-CAM par une nappe flexible et réalise les prises de vue du prototype.

![Dimensions du module caméra OV5640 : longueur de 30 mm, largeur de 8,5 mm et connexion de 5,6 mm](/img/components/ov5640-camera-dimensions.jpg)

*Relevé dimensionnel fourni par le vendeur.*

### Lecteur RFID-RC522 et carte NFC

Le module RFID-RC522 et la carte NFC ont été fournis avec leurs dimensions et sont déjà en notre possession. Les mesures ont donc pu être vérifiées directement sur les éléments reçus.

La carte NFC mesure 85 × 54 mm. Le module RFID-RC522 mesure 60 × 40 mm : cette seconde dimension est la plus importante pour concevoir son logement dans le prototype.

![Dimensions de la carte NFC et du module RFID-RC522 : carte de 85 × 54 mm et module de 60 × 40 mm](/img/components/rfid-rc522-nfc-dimensions.png)

### LED RGB 5 mm

Le relevé fournisseur indique un boîtier de 4,8 mm de largeur et 5,5 mm de hauteur.

![Dimensions et brochage de la LED RGB 5 mm](/img/components/led-rgb-dimensions.png)
