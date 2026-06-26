# Patch 040 — Correctif `flutter analyze` après le patch 039

Ce correctif supprime deux méthodes `_loadExportContext()` insérées par erreur dans des widgets stateless de l’écran d’export JSON. Ces méthodes faisaient référence à `widget`, `_activityRepository`, `_userRepository` et `_assignmentRepository` hors de leur classe d’état, ce qui bloquait `flutter analyze` et le build.

Le patch :

- conserve le chargement du contexte d’export dans `_AssessmentExportScreenState` ;
- supprime les duplications invalides ;
- ajoute l’affichage du nombre d’affectations dans la carte d’export ;
- remplace les usages dépréciés de `value:` par `initialValue:` dans les `DropdownButtonFormField` ;
- nettoie quelques alertes `const` dans les tests.
