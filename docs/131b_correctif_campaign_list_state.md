# Patch 131B — Correctif CampaignListState

Ce correctif réintroduit la classe privée `_CampaignListState` utilisée par `CampaignListScreen` après le patch 131.

Le patch 131 référençait ce type pour le `FutureBuilder`, mais la classe n’était pas déclarée dans le fichier, ce qui bloquait `flutter analyze` et `flutter run`.

Fichier modifié :

- `flutter/lib/presentation/campaigns/campaign_list_screen.dart`
