# Monitoring Kibana OpenIRN

Ce répertoire contient une définition portable du dashboard et des règles
d'alerte OpenIRN. Aucun nom d'hôte, URL publique, identifiant de moniteur,
identifiant de connecteur ou secret propre à une instance n'est versionné.

Le déploiement a été validé avec Kibana 9.5.2. Une autre version doit exposer
les mêmes API Dashboard, Alerting et Connectors ainsi que le type de règle
`.es-query`.

## Prérequis de données

Les scripts ne configurent pas Fleet et ne créent pas de données. Avant
l'installation, les flux suivants doivent exister :

- `logs-openirn.api-*`, alimenté par `api-access.ndjson` avec
  `event.dataset: openirn.api` et `service.name: openirn-api` ;
- `logs-openirn.security-*`, alimenté par `security.ndjson` avec
  `event.dataset: openirn.security` et `service.name: openirn-api` ;
- `synthetics-http-*`, avec un moniteur HTTP portant
  `service.name: openirn-api` ;
- `metrics-system.cpu-*`, `metrics-system.memory-*` et
  `metrics-system.filesystem-*` ;
- `metrics-mysql.status-*`.

Les suffixes sont des jokers afin de ne dépendre d'aucun namespace Fleet. Les
métriques System et MySQL de l'instance doivent partager la même valeur ECS
`host.name`. Cette valeur est le seul paramètre obligatoire du rendu.

Vérifier les prérequis dans Dev Tools :

```text
FROM logs-openirn.api-*, logs-openirn.security-*, synthetics-http-*,
     metrics-system.cpu-*, metrics-system.memory-*,
     metrics-system.filesystem-*, metrics-mysql.status-*
| STATS documents = COUNT(*) BY data_stream = CONCAT(data_stream.type, "/", data_stream.dataset, "/", data_stream.namespace)
| SORT data_stream
```

Identifier ensuite la valeur `host.name` réellement reçue :

```text
FROM metrics-system.cpu-*
| STATS documents = COUNT(*) BY host.name
| SORT documents DESC
```

## Installation complète

Sur l'hôte Kibana, cloner le dépôt ou copier le répertoire `monitoring/kibana`,
puis exécuter :

```bash
cd /chemin/vers/OpenIRN
export KIBANA_URL=http://127.0.0.1:5601
export OPENIRN_MONITORED_HOST=openirn-api.example.org
IFS= read -r -s 'KIBANA_API_KEY?Clé API Kibana : '
printf '\n'
export KIBANA_API_KEY
monitoring/kibana/install-monitoring.sh
unset KIBANA_API_KEY KIBANA_URL OPENIRN_MONITORED_HOST
```

La clé doit pouvoir :

- lire les data streams supervisés ;
- créer ou modifier un dashboard ;
- lire, créer et modifier des règles Kibana ;
- lire et, si nécessaire, créer un connecteur `.server-log`.

La clé n'est écrite dans aucun fichier par les scripts et n'apparaît pas dans
les arguments de `curl`. Ne jamais l'ajouter à un fichier versionné, à la ligne
de commande ou à l'historique du shell.

## Dashboard

`openirn-api-health-security.json` est la source de vérité générique du
dashboard `OpenIRN — Santé API et sécurité`. Le jeton
`__OPENIRN_MONITORED_HOST__` est remplacé uniquement dans un fichier temporaire
par `deploy-dashboard.sh`.

Déployer seulement le dashboard :

```bash
monitoring/kibana/deploy-dashboard.sh
```

L'identifiant stable par défaut est `openirn-api-health-security`. Il peut être
surchargé avant la première installation :

```bash
export OPENIRN_DASHBOARD_ID=openirn-api-health-security
```

L'opération remplace intégralement le dashboard portant cet identifiant.
Exporter son état courant avant de redéployer après une modification manuelle.

## Règles d'alerte

`openirn-alerting-rules.json` définit onze règles ES|QL. Le script
`deploy-alerting-rules.sh` crée les règles absentes et met à jour les règles
existantes sans réactiver une règle volontairement désactivée.

Par défaut, le script recherche le connecteur local
`OpenIRN monitoring - Kibana log` et le crée s'il n'existe pas. Ce connecteur
n'envoie aucune donnée vers un service externe. Pour réutiliser un connecteur
`.server-log` existant :

```bash
export KIBANA_CONNECTOR_ID=identifiant-du-connecteur
monitoring/kibana/deploy-alerting-rules.sh
unset KIBANA_CONNECTOR_ID
```

Il est aussi possible de sélectionner un connecteur par son nom ou d'interdire
sa création automatique :

```bash
export OPENIRN_SERVER_LOG_CONNECTOR_NAME='Journal local OpenIRN'
export OPENIRN_CREATE_SERVER_LOG_CONNECTOR=false
```

## Contrôle hors ligne et portabilité

Les modes `--render` n'appellent aucune API et n'exigent aucune clé :

```bash
OPENIRN_MONITORED_HOST=api-node.example.net \
	monitoring/kibana/deploy-dashboard.sh --render | jq -e . >/dev/null

OPENIRN_MONITORED_HOST=api-node.example.net \
	monitoring/kibana/deploy-alerting-rules.sh --render | jq -e . >/dev/null

monitoring/kibana/validate-monitoring.sh
```

Le dernier script rend les deux définitions avec un nom d'hôte alternatif,
contrôle les jokers de namespace, recherche les références propres à une
infrastructure et refuse les formes usuelles de secrets intégrés.

Les procédures d'intervention sont décrites dans `RUNBOOK_ALERTES.md` et
`RUNBOOK_ALERTS.en.md`.
