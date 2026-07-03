# Patch 155 — Demandes d’enrôlement des terminaux

Ce patch ajoute un flux de demande d’enrôlement pour les terminaux non encore autorisés.

## Objectifs

- Un utilisateur qui ne dispose pas encore d’un code d’appairage peut demander l’autorisation du terminal.
- La demande apparaît dans le cartouche **Terminaux autorisés** du menu **Administration**.
- Le Pilote IRN voit les demandes et terminaux de son espace de travail.
- L’Administrateur solution voit les demandes, terminaux et utilisateurs de tous les espaces.
- Le Pilote IRN dispose aussi des cartouches **Terminaux autorisés** et **Utilisateurs** dans son menu Administration.

## Côté terminal

Dans l’écran **Autoriser ce terminal**, un bouton **Demander une autorisation** crée une demande d’enrôlement associée à l’espace de travail choisi.

La demande contient uniquement :

- l’espace de travail ;
- le nom du terminal ;
- la plateforme ;
- une note optionnelle côté API.

## Côté Administration

Dans **Administration → Terminaux autorisés** :

- les demandes en attente apparaissent au-dessus des terminaux ;
- un Pilote IRN peut approuver ou refuser les demandes de son espace ;
- l’Administrateur solution peut consulter tous les espaces ;
- l’approbation génère un code d’appairage court, à usage unique.

Dans **Administration → Utilisateurs** :

- le Pilote IRN gère les utilisateurs de son espace ;
- l’Administrateur solution affiche les utilisateurs de tous les espaces.

## Fichiers principaux

- `server/openirn-api/app/main.py`
- `server/openirn-api/sql/schema.sql`
- `flutter/lib/data/api/openirn_api_client.dart`
- `flutter/lib/domain/models/device_enrollment_request.dart`
- `flutter/lib/presentation/admin/authorized_devices_screen.dart`
- `flutter/lib/presentation/sync/device_enrollment_screen.dart`
- `flutter/lib/presentation/users/user_list_screen.dart`
