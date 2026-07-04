# Patch 167.2 — Isolation de l’enrôlement des terminaux

## Objectif

Le patch 167 avait introduit une identité stable du terminal pour permettre une
vue globale lisible : un même terminal peut apparaître une seule fois avec la
liste des espaces dans lesquels il est autorisé.

Le comportement attendu est cependant strict : l’identité du terminal peut être
globale, mais son autorisation reste propre à chaque espace de travail.

Un terminal enrôlé dans un espace ne doit donc jamais être automatiquement
autorisé dans un autre espace.

## Changements serveur

- La synchronisation automatique des administrateurs de solution ne copie plus
  les terminaux actifs entre espaces.
- La création d’un nouvel espace ne donne plus automatiquement accès au terminal
  utilisé pour créer cet espace.
- L’enrôlement reste porté par la clé logique `(tenant_id, device_id)` dans
  `authorized_devices`.
- La vue globale des terminaux continue de regrouper les lignes par `device_id`
  pour l’affichage, sans modifier l’isolation d’accès.

## Nettoyage des autorisations créées par l’ancien comportement

Les anciennes autorisations propagées automatiquement portaient l’identifiant
d’enrôlement technique suivant :

```text
 tenant-bootstrap
```

Le patch ajoute l’outil :

```bash
server/openirn-api/tools/cleanup_cross_tenant_device_authorizations.py
```

Par défaut, il ne supprime rien :

```bash
sudo -u www-data env \
  OPENIRN_API_MYSQL_URL="$OPENIRN_API_MYSQL_URL" \
  /opt/openirn-api/.venv/bin/python \
  tools/cleanup_cross_tenant_device_authorizations.py
```

Suppression contrôlée :

```bash
sudo -u www-data env \
  OPENIRN_API_MYSQL_URL="$OPENIRN_API_MYSQL_URL" \
  /opt/openirn-api/.venv/bin/python \
  tools/cleanup_cross_tenant_device_authorizations.py --apply
```

L’outil supprime uniquement les lignes `authorized_devices` dont
`enrollment_id = 'tenant-bootstrap'`. Les terminaux enrôlés explicitement par
code ou par demande d’enrôlement ne sont pas touchés.

Chaque suppression écrit une entrée d’audit `device.auto_authorization_removed`.

## Effet attendu

Après nettoyage :

- un terminal enrôlé dans `Défaut` n’est pas autorisé dans `Groupe La Poste` ;
- un terminal enrôlé dans `Groupe La Poste` n’est pas autorisé dans `Défaut` ;
- si le même terminal est volontairement enrôlé dans deux espaces, la vue globale
  l’affiche une seule fois avec deux badges d’espace ;
- la révocation ou l’absence d’autorisation reste propre à chaque espace.
