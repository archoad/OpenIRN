# Patch 123B-c — Accueil terminal non enrôlé

## Objectif

Corriger l'écran d'accueil lorsqu'un terminal n'est pas configuré, n'est pas autorisé par le serveur ou a été révoqué.

Dans ces états, l'application ne doit afficher qu'une seule action : **Autoriser ce terminal**.

## Comportement corrigé

- Terminal jamais appairé : seul le cartouche **Autoriser ce terminal** apparaît.
- Terminal connu localement mais révoqué côté serveur : seul le cartouche **Autoriser ce terminal** apparaît.
- Terminal connu localement mais refusé par l'API serveur : seul le cartouche **Autoriser ce terminal** apparaît.
- Les cartouches **Administration**, **Evaluation Indice de Résilience Numérique** et **Référentiel aDRI IRN** sont masqués dans ces cas.
- Les actions protégées conservent un garde-fou : si elles sont appelées indirectement, elles refusent l'accès tant que le terminal doit être appairé.

## Détail technique

Le bootstrap de l'accueil distingue maintenant deux situations différentes :

1. Référentiel serveur absent ou indisponible, mais terminal appairé.
2. Terminal non autorisé, révoqué ou nécessitant un appairage.

Seule la seconde situation déclenche l'écran minimal d'appairage.
