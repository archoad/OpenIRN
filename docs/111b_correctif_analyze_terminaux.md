# Patch 111B-b — Correctif analyze page Terminaux autorisés

Ce correctif ajuste la page `Terminaux autorisés` ajoutée par le patch 111B.

Corrections :

- remplacement de l'appel inexistant `responsiveAutofocus(context)` par `shouldAutofocusTextField(context)` ;
- conservation du helper responsive déjà utilisé par les autres dialogues ;
- remplacement de `value:` par `initialValue:` dans `DropdownButtonFormField`, conformément à Flutter 3.33+.

Le patch ne modifie pas la logique d'enrôlement des terminaux.
