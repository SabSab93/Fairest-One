---
title: Idée et inspirations
sidebar_position: 2
description: Origine du miroir connecté et références ayant guidé le projet.
---

# Idée et inspirations

## Le point de départ

À la suite des difficultés rencontrées par Valérie lors d'un essayage de lunettes, nous avons voulu proposer une solution sous la forme d'un miroir connecté. Ce projet nous permet également de mettre en pratique les notions abordées en cours en associant le développement d'une application, la programmation de l'ESP32 et l'utilisation de plusieurs composants électroniques, notamment une caméra, un lecteur RFID, des LED et un buzzer.

Le nom **Fairest One** est un clin d'œil à la célèbre réplique :

> “Mirror, mirror on the wall, who is the fairest one of all?”

## Source

[**Make a Smart Mirror from an Old Tablet**](https://www.youtube.com/watch?v=cFbQzbF69eU&t=33s), publiée par la chaîne **Adam Builds**, présente la fabrication d'un miroir intelligent à partir d'une ancienne tablette. Elle nous a servi de référence pour réfléchir à l'intégration d'un écran derrière une surface réfléchissante et à la conception générale du prototype.


## De l'idée initiale au POC

Notre idée initiale était de réaliser un miroir magique proche d'un produit final. Une tablette ou un écran placé derrière la surface réfléchissante devait afficher un décompte avant la prise de vue ainsi qu'un guide ovale pour aider le client à centrer son visage.

Nous avions également imaginé un éclairage tout autour du miroir afin d'obtenir une photo bien éclairée, à la manière d'un flash. Sa couleur aurait évolué selon l'état du dispositif : éclairage discret en veille, animation pendant le décompte, confirmation après la prise de vue ou signal rouge en cas de problème. D'autres retours visuels et sonores devaient rendre l'expérience aussi claire et autonome que possible.

Au fil de la réflexion, le délai de réalisation et le budget disponible nous ont conduits à recentrer le projet sur ses fonctions essentielles. Le résultat présenté est donc un POC : il doit démontrer le fonctionnement et l'intérêt du concept, sans chercher à intégrer immédiatement toutes les fonctionnalités imaginées. Ce recentrage est détaillé dans la partie [Composants et budget](./bom).

