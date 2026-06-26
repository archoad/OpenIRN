# Patch 066 — correctif AppBar responsive

Ce patch corrige les effets de bord du patch 065 sur `assessment_screen.dart`.

Objectifs :

- supprimer les méthodes de navigation injectées au mauvais endroit ;
- réinsérer une seule version de ces méthodes dans `_AssessmentScreenState` ;
- remplacer la barre d’actions large par un menu `⋮` ;
- conserver le titre centré et tronqué proprement sur mobile ;
- éviter les `RenderFlex overflow` dans l’AppBar sur iPhone.

Application :

```bash
unzip -o irn_starter_kit_patch_066.zip
python3 tools/repair_patch065_assessment_appbar.py
cd flutter
flutter clean
flutter pub get
flutter analyze
flutter test
flutter run -d macos
flutter run -d 00008110-00084C340A61401E
```
