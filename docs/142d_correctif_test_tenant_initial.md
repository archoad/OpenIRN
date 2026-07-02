# Patch 142D — Correctif test tenant initial

## Contexte

Depuis le patch 142C, OpenIRN démarre volontairement **sans tenant sélectionné**.
Le tenant `default` reste permanent côté serveur, mais il ne doit plus être imposé au lancement côté Flutter.

## Correction

Le test `LocalSyncConfigurationRepository` attendait encore `tenantId == default` lorsque la configuration locale est vide.
Cette attente est obsolète avec le nouveau flux :

1. démarrage sans tenant ;
2. choix explicite du tenant ;
3. contrôle de l'appairage ;
4. affichage des utilisateurs ou écran d'autorisation du terminal.

Le patch met donc le test en cohérence avec le comportement attendu :

```dart
expect(configuration.tenantId, isEmpty);
```

## Portée

Aucun changement fonctionnel applicatif. Le patch ne modifie que le test et ajoute ce document.
