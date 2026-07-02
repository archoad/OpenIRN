# Patch 153 — Export PDF de la synthèse IRN

Ce patch complète le patch 152.

## Corrections PNG

Les boutons **Exporter en PNG** des cartouches **Indicateurs IRN** et **Radar IRN** sont masqués pendant la capture.

Résultat : le bouton n'apparaît plus dans l'image PNG exportée.

## Export PDF

La page **Campagnes → Synthèse** propose désormais un bouton :

- **Exporter la synthèse PDF**

L'export PDF produit un document de synthèse contenant :

- l'identité de la campagne ;
- le référentiel utilisé ;
- le score global ;
- les indicateurs par pilier ;
- une lecture tabulaire du radar IRN ;
- la répartition par portée ;
- les points forts provisoires ;
- les points d'attention provisoires ;
- une note méthodologique sur le score OpenIRN R/NR non pondéré.

## Dépendance ajoutée

Le patch ajoute la dépendance Dart/Flutter :

```yaml
pdf: ^3.13.0
```

Après application du patch, lancer :

```bash
cd flutter
flutter pub get
flutter analyze
```

## Fichiers modifiés / ajoutés

- `flutter/pubspec.yaml`
- `flutter/lib/presentation/assessment/assessment_summary_screen.dart`
- `flutter/lib/data/files/local_pdf_file_service.dart`
- `flutter/lib/domain/services/assessment_pdf_export_service.dart`
- `docs/153_export_pdf_synthese.md`
