# Patch 050 — nettoyage const redondant

Corrige le dernier avertissement `flutter analyze` dans `access_policy_service_test.dart` : suppression d'un `const` imbriqué inutile dans une expression déjà constante.
