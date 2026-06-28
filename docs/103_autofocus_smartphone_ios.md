# Patch 103 — Autofocus adapté aux smartphones iOS

## Objectif

Limiter l'ouverture automatique du clavier virtuel sur smartphone lorsque l'application affiche une boîte de dialogue contenant un champ texte.

Sur iOS, l'ouverture automatique du clavier peut générer des avertissements UIKit du type :

```text
TUIKeyplane.right.width == - 1.5
Will attempt to recover by breaking constraint
```

Ces avertissements viennent du clavier système iOS, mais ils polluent les logs et peuvent donner l'impression d'un bug applicatif.

## Changements

Ajout du helper :

```text
flutter/lib/presentation/common/responsive_autofocus.dart
```

Ce helper conserve l'autofocus sur écran large, mais le désactive sur smartphone.

Fichiers mis à jour :

```text
flutter/lib/presentation/admin/server_maintenance_screen.dart
flutter/lib/presentation/assessment/assessment_screen.dart
flutter/lib/presentation/users/user_list_screen.dart
flutter/lib/presentation/campaigns/campaign_management_screen.dart
flutter/lib/presentation/campaigns/campaign_list_screen.dart
```

## Effet attendu

Sur smartphone :

- le clavier ne s'ouvre plus automatiquement dès l'affichage d'un dialogue ;
- l'utilisateur tape dans le champ pour ouvrir le clavier ;
- les avertissements UIKit liés à `TUIKeyplane` devraient disparaître ou être fortement réduits.

Sur tablette, desktop ou grand écran :

- l'autofocus reste actif pour conserver le confort d'usage.
