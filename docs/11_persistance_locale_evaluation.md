# Patch 009 — Persistance locale de l’évaluation R / NR

Ce patch ajoute une première sauvegarde locale de l’évaluation officielle R / NR.

## Objectif

L’évaluation saisie dans l’écran `Évaluation R / NR` est désormais restaurée au redémarrage de l’application.

## Choix technique provisoire

Pour ce jalon, la persistance utilise `shared_preferences`.

Ce choix est volontairement simple :

- pas de serveur ;
- pas de base SQLite pour l’instant ;
- pas de campagne entreprise ;
- uniquement le référentiel officiel aDRI et des réponses locales de test.

La future version multi-utilisateurs/offline-first migrera cette logique vers SQLite/Drift avec une table d’outbox de synchronisation.

## Données sauvegardées

Les réponses sont stockées par référentiel :

```json
{
  "schemaVersion": 1,
  "referentialId": "adri-irn-v1.1",
  "updatedAt": "2026-06-22T14:00:00Z",
  "answers": {
    "RES-1.1": "resilient",
    "RES-1.2": "nonResilient"
  }
}
```

Les critères `N.C.` ne sont pas stockés. Leur absence équivaut à `notAnswered`.

## Commandes

```bash
cd flutter
flutter clean
flutter pub get
flutter test
flutter run -d macos
```
