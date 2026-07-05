# Patch 179.1 — Correctif BuildContext async dans la création de campagne

Ce micro-patch corrige l'avertissement Flutter `use_build_context_synchronously`
introduit pendant l'internationalisation des campagnes.

## Correction

Le libellé traduit `Campagne créée` est maintenant évalué avant les appels
asynchrones de création de campagne et de synchronisation, puis réutilisé dans
l'événement d'activité.

Cela évite d'utiliser `BuildContext` après un `await`.

## Fichiers modifiés

- `flutter/lib/presentation/campaigns/campaign_management_screen.dart`
