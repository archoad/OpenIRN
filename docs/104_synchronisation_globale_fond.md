# Patch 104 — Synchronisation globale en tâche de fond

Ce patch déplace la surveillance automatique de synchronisation au niveau de l’application.

Avant ce patch, l’écoute temps réel SSE et le polling de secours étaient actifs uniquement lorsqu’une campagne était ouverte. Un smartphone resté sur l’accueil, la liste des campagnes, le référentiel, la page utilisateurs ou la maintenance ne récupérait donc pas automatiquement les modifications publiées par un autre terminal.

## Nouveau fonctionnement

Au chargement du référentiel, OpenIRN démarre un coordinateur global `AppSyncCoordinator`.

Ce coordinateur reste actif pendant toute l’utilisation de l’application :

- écoute du flux SSE `/sync/events` quand la configuration API est complète ;
- polling de secours toutes les 45 secondes ;
- import automatique du dernier snapshot serveur lorsqu’il provient d’un autre terminal ;
- notification des écrans ouverts pour qu’ils rechargent leurs données locales ;
- publication différée des modifications locales utilisateurs.

## Écrans mis à jour

Les écrans suivants se rafraîchissent automatiquement après import d’un snapshot distant :

- page `Campagnes` ;
- page `Gérer les campagnes` ;
- page `Utilisateurs` ;
- campagne ouverte.

La page `Synchronisation API` relance aussi le coordinateur global après sauvegarde de la configuration.

## Limite volontaire

Il ne s’agit pas d’une tâche iOS/Android continuant quand l’application est suspendue par le système. Le coordinateur fonctionne tant que l’application est ouverte ou revenue au premier plan.
