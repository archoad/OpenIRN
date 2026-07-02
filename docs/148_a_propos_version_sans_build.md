# Patch 148 — À propos : version sans numéro de build

## Objectif

La page **À propos** affichait la version Flutter complète sous la forme :

```text
0.6.0+xx
```

Pour une lecture plus claire côté utilisateur, elle affiche désormais uniquement la version applicative :

```text
0.6.0
```

## Détail

Le patch ne modifie pas `pubspec.yaml` et ne change pas les métadonnées de build. Il change uniquement le format d'affichage dans la page **À propos**.
