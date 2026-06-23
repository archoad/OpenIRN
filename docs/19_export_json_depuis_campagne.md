# Patch 017 — Export JSON depuis la page de campagne

Ce patch déplace l'accès à l'export JSON.

## Avant

L'export JSON était accessible depuis l'écran de synthèse.

```text
Campagne locale → Synthèse → Export JSON
```

## Après

L'export JSON est accessible directement depuis la page de campagne locale, à côté du bouton `Synthèse`.

```text
Campagne locale → Export JSON
Campagne locale → Synthèse
```

## Modifications

- `assessment_screen.dart` importe et ouvre désormais `AssessmentExportScreen` depuis l'AppBar.
- `assessment_summary_screen.dart` ne propose plus l'action `Export JSON`.

Le contenu exporté reste inchangé : référentiel, campagne, réponses, justifications et scores.
