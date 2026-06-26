# Patch 043 — Affectations limitées aux évaluateurs

Ce patch limite la liste proposée dans les menus d'affectation aux seuls utilisateurs actifs ayant le rôle `Évaluateur`.

## Comportement

- l'écran `Affectations` ne propose plus les profils Administrateur, Pilote IRN, Validateur ou Lecteur dans les listes déroulantes ;
- le compteur d'utilisateurs affiché devient `Évaluateurs actifs` ;
- le compteur de critères affectés ne comptabilise que les affectations vers des évaluateurs actifs ;
- un chip d'alerte `Aucun évaluateur actif` apparaît si aucun profil évaluateur n'est disponible ;
- les affectations existantes vers un profil non évaluateur ne sont plus sélectionnables dans le menu et doivent être réaffectées à un évaluateur.

Cette règle prépare le futur modèle de droits : les pilotes et administrateurs gèrent la campagne, tandis que les évaluateurs reçoivent les critères à renseigner.
