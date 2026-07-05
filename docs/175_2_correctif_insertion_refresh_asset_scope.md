# Patch 175.2 — Correctif insertion refresh criticité actifs

Ce correctif retire deux insertions erronées de `_refreshAssetScopeFromInventory()` qui avaient été ajoutées hors de l'état principal de l'écran d'évaluation.

La méthode reste présente une seule fois dans `_AssessmentScreenState`, où les champs `_campaign`, `_apiClient`, `_configurationRepository` et `_isAssetScopedCampaign` existent réellement.

Aucun changement serveur ni base de données.
