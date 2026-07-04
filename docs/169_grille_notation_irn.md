# Patch 169 — Grille de notation IRN

Ce patch remplace l’ancien modèle binaire `R / NR` par la grille de notation transmise par les porteurs de la norme IRN.

## Grille appliquée

| Niveau | Libellé | Valeur score |
| --- | --- | ---: |
| N.C. | Non concerné | exclu du score |
| NR | Non résilient | 10/100 |
| Intention | Intention | 25/100 |
| Moyen | Moyen | 50/100 |
| Résultat | Résultat | 95/100 |

OpenIRN conserve aussi un état interne `Non renseigné`, qui correspond à l’absence de note. Cet état n’est pas proposé comme niveau de notation et sert à distinguer un critère non évalué d’un critère explicitement marqué `N.C.`.

## Calcul

Le score IRN affiché est la moyenne simple des valeurs numériques renseignées :

```text
score = somme(notes numériques) / nombre de critères notés numériquement
```

Les critères `N.C.` sont exclus du score, mais inclus dans la complétude parce qu’ils sont explicitement renseignés.

Aucune pondération additionnelle par pilier, portée ou criticité n’est appliquée dans ce patch.

## Migration des anciennes notes

Pour simplifier la migration depuis l’ancien modèle `R / NR`, les notes existantes sont effacées dans les campagnes MariaDB déjà présentes.

Après déploiement serveur, exécuter d’abord en mode simulation :

```bash
cd /opt/openirn-api

sudo -u www-data env \
  OPENIRN_API_MYSQL_URL="$OPENIRN_API_MYSQL_URL" \
  /opt/openirn-api/.venv/bin/python tools/reset_irn_ratings_for_169.py
```

Puis appliquer :

```bash
sudo -u www-data env \
  OPENIRN_API_MYSQL_URL="$OPENIRN_API_MYSQL_URL" \
  /opt/openirn-api/.venv/bin/python tools/reset_irn_ratings_for_169.py --apply
```

L’outil conserve :

- les campagnes ;
- les informations de campagne ;
- les affectations ;
- les utilisateurs ;
- les terminaux ;
- le journal d’activité.

Il remet à zéro uniquement les listes `answers` des payloads de campagnes, révisions et snapshots serveur.
