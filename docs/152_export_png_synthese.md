# Patch 152 — Export PNG depuis la synthèse de campagne

Ce patch ajoute, dans le menu **Synthèse** d’une campagne, un bouton d’export PNG pour chacun des deux cartouches principaux :

- **Indicateurs IRN**
- **Radar IRN**

## Fonctionnement

Chaque cartouche dispose désormais de son propre bouton **Exporter en PNG**.

Lors de l’export :

- le cartouche affiché à l’écran est capturé en image ;
- l’utilisateur choisit l’emplacement et le nom du fichier ;
- le fichier est enregistré au format **PNG**.

## Fichiers modifiés

- `flutter/lib/presentation/assessment/assessment_summary_screen.dart`
- `flutter/lib/data/files/local_image_file_service.dart`
- `docs/152_export_png_synthese.md`
