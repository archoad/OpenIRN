# Patch 059 — Import contrôlé d’un snapshot distant

Ce patch ajoute l’import local d’un snapshot récupéré via `GET /sync/pull`.

## Objectif

Après un `POST /sync/push`, le serveur conserve un snapshot complet. OpenIRN peut maintenant :

1. récupérer les snapshots distants ;
2. afficher les snapshots disponibles ;
3. importer explicitement un snapshot ;
4. créer des copies locales des campagnes contenues dans le snapshot ;
5. importer les réponses, justifications, affectations, utilisateurs et journaux d’activité associés.

## Règles d’import

L’import est volontairement non destructeur :

- aucune campagne locale existante n’est écrasée ;
- chaque campagne distante est copiée avec un nouvel identifiant local `remote-import-*` ;
- les utilisateurs distants sont fusionnés avec l’annuaire local par identifiant ;
- l’administrateur local est conservé ;
- les affectations sont importées uniquement si l’utilisateur cible existe dans le snapshot ;
- le référentiel et le checksum sont vérifiés avant import.

## Workflow

Dans OpenIRN :

```text
Campagnes locales
→ Synchronisation
→ Récupérer
→ Importer
```

Une confirmation est affichée avant toute écriture locale.

## Limite volontaire

Ce patch ne met pas encore en place de résolution de conflit bidirectionnelle. Il s’agit d’un import de copie locale, pas d’un merge collaboratif temps réel.

La prochaine étape sera d’ajouter un journal de synchronisation local pour tracer les push, pull et imports distants.
