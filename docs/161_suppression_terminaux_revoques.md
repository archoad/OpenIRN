# Patch 161 — Suppression réelle des terminaux révoqués

Ce patch modifie le comportement de révocation des terminaux autorisés.

## Nouveau comportement

Lorsqu’un administrateur ou un Pilote IRN révoque un terminal depuis :

```text
Administration → Terminaux autorisés
```

le terminal n’est plus simplement marqué comme `revoked` dans la table `authorized_devices`.
Il est désormais supprimé de cette table.

Le jeton du terminal devient immédiatement inutilisable, car la ligne contenant son empreinte n’existe plus.

## Traçabilité

L’événement de sécurité reste conservé dans `device_audit_log` avec le type :

```text
device.revoked
```

Le journal garde les informations utiles : nom du terminal, plateforme, état précédent, date de suppression et identifiant d’enrôlement éventuel.

## Migration automatique

Au démarrage du serveur, les anciens terminaux déjà marqués comme révoqués par les versions précédentes sont supprimés automatiquement de `authorized_devices`.

Un événement `device.deleted` est ajouté dans le journal d’audit pour chaque terminal nettoyé par cette migration.
