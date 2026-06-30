# Patch 124 — Bootstrap d’enrôlement terminal

Ce patch ajoute une procédure de secours lorsque plus aucun terminal OpenIRN actif ne peut ouvrir `Administration → Terminaux autorisés`.

## Principe

Le `deviceId` n’est pas un secret. En revanche, pour créer une invitation d’enrôlement sans terminal existant, il faut disposer d’un accès système au serveur OpenIRN et à sa base SQLite.

Le patch ajoute donc un outil serveur :

```bash
server/openirn-api/tools/create_bootstrap_enrollment.py
```

Il crée directement dans SQLite un code d’enrôlement temporaire, à usage unique, compatible avec l’écran `Autoriser ce terminal` de l’application.

## Utilisation

Sur le serveur hébergeant l’API OpenIRN :

```bash
cd /chemin/vers/OpenIRN/server/openirn-api
sudo python3 tools/create_bootstrap_enrollment.py \
  --db /var/lib/openirn-api/openirn.sqlite3 \
  --tenant archoad \
  --label "Bootstrap MacBook" \
  --expires 10
```

Durées autorisées : `5`, `10` ou `15` minutes.

Si des terminaux actifs existent encore, l’outil refuse par défaut. Pour un vrai mode break-glass :

```bash
sudo python3 tools/create_bootstrap_enrollment.py \
  --db /var/lib/openirn-api/openirn.sqlite3 \
  --tenant archoad \
  --label "Break-glass" \
  --expires 10 \
  --force
```

## Côté application

Sur le terminal à réautoriser :

```text
Accueil → Autoriser ce terminal → saisir le code affiché par le script
```

Une fois le terminal enrôlé, utiliser ensuite le parcours normal :

```text
Administration → Terminaux autorisés → Autoriser un nouveau terminal
```

## Sécurité

- Le code est à usage unique.
- Le code expire rapidement.
- Le code n’est pas stocké en clair dans SQLite.
- L’opération est journalisée dans `device_audit_log` quand la table est disponible.
- Le script nécessite un accès OS au serveur et à la base SQLite.
