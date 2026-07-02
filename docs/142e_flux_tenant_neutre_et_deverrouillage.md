# Patch 142E — Flux tenant neutre et déverrouillage tenant courant

## Objectif

Corriger deux régressions UX introduites par le passage au multi-tenant :

1. Au démarrage, avant le choix du tenant, l'application ne doit pas afficher un statut API hérité d'un ancien tenant.
2. Après choix d'un tenant déjà appairé, le bouton **Déverrouiller OpenIRN** doit afficher les utilisateurs de ce tenant, sans redemander le choix du tenant.

## Changements

- Le démarrage efface explicitement le contexte tenant/session en mémoire.
- L'indicateur de synchronisation devient neutre lorsqu'aucun tenant n'est sélectionné et n'appelle pas `/sync/status` dans cet état.
- Le déverrouillage utilise directement le tenant déjà sélectionné.
- La boîte de choix tenant n'est plus appelée pendant le déverrouillage.

## Flux attendu

```text
Démarrage
  → aucun tenant sélectionné
  → indicateur neutre
  → cartouche Choisir un tenant

Choix tenant
  → terminal appairé : cartouche Déverrouiller OpenIRN
  → terminal non appairé : cartouches Autoriser ce terminal + Retour au choix du tenant

Déverrouiller OpenIRN
  → utilisateurs actifs du tenant courant
```
