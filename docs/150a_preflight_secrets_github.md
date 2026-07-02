# Patch 150A — Préflight : secrets GitHub

## Objectif

Le préflight `--require-secrets` vérifiait uniquement les variables d'environnement du shell local. C'était trop strict pour le cas normal où les secrets sont stockés dans **GitHub Secrets** et non exportés localement.

## Nouveau comportement

Pour chaque secret attendu, le script accepte maintenant deux sources :

1. variable d'environnement locale, utile dans GitHub Actions ou sur une machine de build ;
2. secret GitHub existant, vérifié par `gh secret list` sans afficher la valeur du secret.

Ainsi, depuis le poste développeur, cette commande peut réussir si les secrets sont configurés dans GitHub :

```bash
./tools/check_openirn_release_preflight.sh --tag v0.6.1 --require-secrets
```

## Sécurité

Le script ne lit jamais le contenu des secrets. Il vérifie uniquement leur nom.
