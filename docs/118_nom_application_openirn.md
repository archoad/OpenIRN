# Patch 118 — Nom applicatif OpenIRN

Ce patch corrige la casse du nom affiché de l’application afin d’utiliser `OpenIRN` de manière homogène sur les plateformes ciblées.

## Modifications

- Android : libellé launcher `OpenIRN`.
- iOS : `CFBundleDisplayName` et `CFBundleName` en `OpenIRN`.
- macOS : `PRODUCT_NAME`, nom de bundle `.app`, titre de fenêtre et `CFBundleDisplayName` en `OpenIRN`.
- Windows : titre de fenêtre, métadonnées de version et nom de binaire en `OpenIRN`.
- README Flutter : titre corrigé en `OpenIRN`.

## Note

Le nom du package Dart dans `pubspec.yaml` reste `openirn`, car les noms de packages Dart doivent rester en minuscules.
