# Patch 160 — Liste des espaces dans `create_bootstrap_enrollment.py`

Ce patch ajoute une option de diagnostic au script serveur :

```bash
python3 server/openirn-api/tools/create_bootstrap_enrollment.py --list-tenants
```

Par défaut, le script lit la base SQLite configurée par `OPENIRN_API_DB`, ou :

```text
/var/lib/openirn-api/openirn.sqlite3
```

Il est aussi possible d’indiquer explicitement la base :

```bash
python3 server/openirn-api/tools/create_bootstrap_enrollment.py \
  --db /var/lib/openirn-api/openirn.sqlite3 \
  --list-tenants
```

La commande affiche les espaces de travail existants avec :

- le nom affiché ;
- l’identifiant technique UUID ;
- le caractère permanent ;
- le nombre d’utilisateurs actifs ;
- le nombre de terminaux actifs ;
- le nombre de demandes d’enrôlement en attente.

Exemple :

```text
OpenIRN tenants
---------------
Database: /var/lib/openirn-api/openirn.sqlite3

Nom affiché  Tenant ID                             Permanent  Utilisateurs  Terminaux  Demandes
-----------  ------------------------------------  ---------  ------------  ---------  --------
Défaut       11111111-1111-4111-8111-111111111111  oui        1             1          0
Archoad      22222222-2222-4222-8222-222222222222  non        4             2          1
```

Le script accepte aussi les anciens alias de tenant lors de la création d’un code d’enrôlement. Par exemple, si `default` a été migré vers un UUID, la commande suivante résout automatiquement l’UUID réel avant de créer le code :

```bash
python3 server/openirn-api/tools/create_bootstrap_enrollment.py \
  --tenant default \
  --force
```
