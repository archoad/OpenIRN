# Patch 106 — Clavier iOS en mode sécurisé

Ce patch renforce le contournement des avertissements UIKit observés sur smartphone iOS :

```text
TUIKeyplane.right.width == - 1.5
```

Le message vient du clavier natif iOS et non directement d'une contrainte Flutter. Pour réduire les risques de décrochage de session debug et de comportement instable, l'application évite désormais les claviers iOS spécialisés sur petit écran.

## Changements

- Ajout d'un helper `safeKeyboardType()` dans `responsive_autofocus.dart`.
- Sur iPhone / écran compact :
  - les champs `number`, `visiblePassword` et `emailAddress` repassent sur un clavier texte standard ;
  - les champs sensibles désactivent autocorrection, suggestions, smart quotes et smart dashes.
- Ajout d'un `KeyboardDismissScope` global dans `main.dart` : un tap hors champ ferme le clavier sans bloquer les interactions.
- Sécurisation des champs suivants :
  - authentification utilisateur ;
  - changement de code utilisateur ;
  - email directeur de projet ;
  - email utilisateur ;
  - token API OpenIRN.

## Objectif

Réduire les avertissements UIKit liés au clavier et éviter que le clavier iOS spécialisé provoque une instabilité sur smartphone pendant l'utilisation de l'application.
