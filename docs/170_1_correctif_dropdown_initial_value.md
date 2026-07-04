# Patch 170.1 — Correctif Flutter DropdownButtonFormField

Ce correctif remplace l'usage déprécié de `DropdownButtonFormField.value` par `initialValue` dans l'écran de gestion de l'inventaire SI.

## Fichier modifié

- `flutter/lib/presentation/admin/asset_inventory_management_screen.dart`

## Impact

Aucun changement fonctionnel. Le patch supprime uniquement les avertissements `deprecated_member_use` introduits avec les versions récentes de Flutter.
