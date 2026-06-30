# Patch 135 — Historique référentiel officiel

Ce patch ajoute l’historisation serveur des installations du référentiel officiel aDRI IRN.

## Objectif

Jusqu’ici, la table `official_referentials` ne conservait que le référentiel actif. Une nouvelle installation ou une réinstallation remplaçait donc l’état courant sans garder de trace exploitable de l’import précédent.

Le patch 135 conserve maintenant une piste d’audit dédiée pour chaque installation validée du référentiel officiel.

## Stockage serveur

Ajout de la table SQLite :

```text
official_referential_history
```

Chaque entrée conserve :

- l’identifiant d’historique `history_id` ;
- l’identifiant et la version du référentiel ;
- l’état actif au moment de la consultation ;
- le chemin GitLab, la branche et le blob source ;
- les empreintes SHA-256 du fichier source XLSX et du JSON canonique ;
- les dates de téléchargement et d’import ;
- le nombre de piliers et de critères ;
- l’utilisateur ayant déclenché l’installation quand il est connu ;
- le rapport de validation et le payload canonique.

La table active `official_referentials` reste conservée pour la lecture courante de l’application.

## Migration douce

Au démarrage de l’API, le serveur crée automatiquement la table d’historique si elle n’existe pas.

Si un référentiel officiel était déjà installé avant ce patch, il est repris automatiquement dans l’historique lors du démarrage API ou lors de la première consultation de l’historique.

## API ajoutée

```text
GET /referential/official/history?tenantId=default&limit=50
```

L’endpoint exige une autorisation d’administration stricte : session serveur courte Administrateur ou bearer serveur de transition.

Un simple `deviceId` enrôlé ou un ancien jeton terminal ne donne pas accès à cet historique.

## Interface Flutter

La page existante :

```text
Administration → Référentiel officiel aDRI
```

affiche maintenant une carte `Historique référentiel officiel` avec :

- la liste des installations historisées ;
- l’entrée active ;
- la version installée ;
- la date d’installation ;
- l’utilisateur déclencheur quand disponible ;
- les empreintes courtes source et JSON canonique ;
- le blob GitLab.

Le bouton `Réinstaller` force maintenant explicitement une réinstallation quand le serveur est déjà à jour, afin de créer une nouvelle entrée d’historique contrôlée.

## Correctif inclus

Le résumé du référentiel actif expose maintenant aussi l’URL GitLab reconstruite côté serveur (`webUrl`) afin d’aligner l’affichage du référentiel courant avec celui de la version distante.

## Fichiers modifiés

```text
server/openirn-api/app/main.py
server/openirn-api/sql/schema.sql
flutter/lib/domain/models/official_referential.dart
flutter/lib/data/api/openirn_api_client.dart
flutter/lib/presentation/admin/official_referential_screen.dart
docs/135_historique_referentiel_officiel.md
```
