# 115 — Correctif analyse Flutter : contexte après async gap

## Objectif

Corriger l'avertissement Flutter `use_build_context_synchronously` dans la page **Synchronisation API**.

## Correction

La méthode `_forgetLocalAuthorization()` charge la configuration locale avec un `await`, puis ouvre une boîte de dialogue avec `context`.

Le correctif ajoute un garde :

```dart
if (!mounted) {
	return;
}
```

avant l'appel à `showDialog()`.

## Fichier modifié

- `flutter/lib/presentation/sync/sync_screen.dart`
