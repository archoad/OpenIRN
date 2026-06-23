# Patch 015 — Correctif tests export + justifications

Le patch 014 a remplacé le paramètre `answers` de `AssessmentExportService` par `criterionAnswers`, afin de transporter à la fois la réponse R/NR/N.C. et la justification associée.

Le fichier `assessment_export_service_test.dart` utilisait encore l'ancienne signature. Ce patch met à jour le test pour vérifier :

- `schemaVersion: 2` ;
- le passage de `criterionAnswers` ;
- la présence des justifications dans l'export JSON ;
- la compatibilité de `buildPrettyJson` avec le nouveau modèle.
