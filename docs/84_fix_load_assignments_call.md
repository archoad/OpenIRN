# Patch 084 — correction définitive de l'appel `_loadAssignmentsAndUsers`

Ce patch corrige un reliquat du patch 082/083 dans `assessment_screen.dart`.

Il remplace toute référence à :

```dart
_loadAssignmentsAndUsers()
```

par :

```dart
_loadAssignments()
```

Le patch est volontairement livré sous forme de script afin de corriger le fichier local exact, même si les patchs précédents ont laissé un état intermédiaire.
