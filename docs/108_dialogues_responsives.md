# Patch 108 — Dialogues responsives multi-plateformes

Ce patch rend les fenêtres de dialogue plus confortables sur grands écrans tout en conservant un affichage compact sur smartphone.

## Objectif

La fenêtre de création/modification d’un utilisateur était trop étroite sur macOS. Les dialogues concernés utilisent maintenant une largeur calculée à partir de la largeur disponible de l’écran, avec un maximum par type de fenêtre.

## Changements

- ajout de `ResponsiveDialogContent` et des helpers associés dans `presentation/common/responsive_dialog.dart` ;
- largeur proportionnelle à l’écran :
  - smartphone : presque toute la largeur utile ;
  - tablette / iPad : largeur intermédiaire ;
  - desktop macOS / Windows : fenêtre élargie mais plafonnée ;
- formulaire utilisateur élargi jusqu’à 820 px ;
- dialogues d’administration et de synchronisation alignés sur le même comportement ;
- conservation du comportement sécurisé iOS pour le clavier et le pavé PIN.

## Fichiers modifiés

- `flutter/lib/presentation/common/responsive_dialog.dart`
- `flutter/lib/presentation/users/user_list_screen.dart`
- `flutter/lib/presentation/campaigns/campaign_list_screen.dart`
- `flutter/lib/presentation/campaigns/campaign_management_screen.dart`
- `flutter/lib/presentation/admin/server_maintenance_screen.dart`
- `flutter/lib/presentation/admin/campaign_history_screen.dart`
- `flutter/lib/presentation/assessment/assessment_screen.dart`
- `flutter/lib/presentation/activity/activity_log_screen.dart`
- `flutter/lib/presentation/sync/sync_screen.dart`
- `flutter/lib/presentation/sync/sync_log_screen.dart`

## Validation

```bash
cd ~/Desktop/OpenIRN/flutter
flutter analyze
flutter run -d macos
flutter run -d <device-mobile>
```
