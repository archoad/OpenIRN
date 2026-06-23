# Patch 020 — Journal d’activité local

Ce patch ajoute un journal d’activité local par campagne.

## Objectif

Tracer les actions importantes avant l’arrivée du serveur et de la synchronisation API :

- création d’une campagne locale ;
- suppression d’une campagne locale ;
- changement de statut ;
- modification d’une réponse R / NR / N.C. ;
- modification ou suppression d’une justification ;
- réinitialisation des réponses.

Le journal reste volontairement local et simple. Il prépare le futur audit trail serveur.

## Stockage

Les évènements sont stockés avec `shared_preferences`, par référentiel et par campagne :

```text
openirn.activityLog.<referentialId>.<campaignId>
```

Le journal conserve au maximum 300 évènements par campagne.

## Modèle

Nouveau modèle :

```text
LocalActivityEvent
LocalActivityType
```

Types disponibles :

```text
campaign_created
campaign_deleted
campaign_status_changed
answer_changed
justification_changed
answers_reset
```

## Interface

Dans l’écran de campagne locale, un nouveau bouton apparaît :

```text
Journal
```

Il ouvre l’écran `ActivityLogScreen`, qui affiche les évènements les plus récents en premier.

## Limites assumées

Ce journal n’est pas encore un audit trail de conformité :

- pas de signature ;
- pas d’utilisateur ;
- pas de serveur ;
- pas d’immutabilité forte ;
- pas encore exporté dans le JSON.

Ces points seront traités lors de l’ajout du multi-utilisateur et de la synchronisation API.
