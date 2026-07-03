# Patch 157A — Corrections analyse Flutter

Ce correctif nettoie trois alertes remontées après le patch 157 :

- suppression de `_safeIdPart` devenu inutilisé dans `AppUser` ;
- suppression de `_safeIdPart` devenu inutilisé dans `LocalCampaign` ;
- suppression d'une référence erronée à `tenant` dans la création d'un espace de travail.

Le comportement fonctionnel du patch 157 reste inchangé : les UUID restent internes et l'interface affiche les noms métier.
