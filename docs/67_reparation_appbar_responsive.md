# Patch 067 — réparation AppBar responsive

Ce patch répare les effets de bord des patchs 065/066 :

- `OpenIrnAppBarAction` accepte désormais `id` ;
- `OpenIrnAppBarAction.divider()` est disponible ;
- les actions sont rendues dans un menu `⋮` ;
- `assessment_screen.dart` est nettoyé des méthodes de navigation dupliquées ;
- une seule série de méthodes `_openAssignments`, `_openSummary`, `_openExport`, `_openQuality`, `_openActivityLog` est réinjectée dans `_AssessmentScreenState`.

Commande :

```bash
python3 tools/repair_assessment_screen_after_appbar_patch.py
```
