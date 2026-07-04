# Patch 166.1 — Correction Flutter post-MariaDB only

Objectif : supprimer un import Flutter devenu inutilisé après le patch 166.

## Correction

- Suppression de l'import `../common/responsive_autofocus.dart` dans `flutter/lib/presentation/admin/server_maintenance_screen.dart`.

Cette correction ne modifie aucun comportement applicatif.
