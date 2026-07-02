# Patch 153A — Corrections `flutter analyze` après export PDF

Ce correctif supprime les alertes remontées après le patch 153 :

- suppression des imports `dart:typed_data` devenus inutiles ;
- correction de l’utilisation de `BuildContext` après une attente asynchrone dans l’export PNG.

Le comportement fonctionnel ne change pas.
