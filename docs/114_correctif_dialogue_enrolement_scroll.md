# Patch 114 — Correctif affichage dialogue d’enrôlement

## Objectif

Corriger le débordement vertical dans la fenêtre **Autoriser un nouveau terminal** de la page **Administration → Terminaux autorisés**.

## Correction

Le contenu du dialogue d’enrôlement est désormais placé dans un `SingleChildScrollView`.

Cela évite les erreurs Flutter du type :

```text
A RenderFlex overflowed by ... pixels on the bottom
```

## Fichier modifié

- `flutter/lib/presentation/admin/authorized_devices_screen.dart`
