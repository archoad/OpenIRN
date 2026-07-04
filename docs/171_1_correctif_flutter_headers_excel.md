# Patch 171.1 — Correctif Flutter export Excel

Ce correctif résout trois remontées `flutter analyze` / `flutter test` introduites par le patch 171.

## Corrections

- Remplacement de l'accès à `HttpHeaders.contentDispositionHeader`, non disponible dans certains SDK Dart, par la clé HTTP standard `content-disposition`.
- Remplacement de `response.headers.map`, non exposé par `HttpHeaders`, par une conversion explicite via `HttpHeaders.forEach`.
- Suppression de l'import inutile `dart:typed_data` dans `local_excel_file_service.dart`.

## Périmètre

Aucun changement fonctionnel côté serveur ni sur le format Excel. Le correctif concerne uniquement la compatibilité Flutter/Dart du client.
