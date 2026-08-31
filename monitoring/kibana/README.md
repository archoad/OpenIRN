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
- `logs-openirn.operations-*`, alimenté par `operations.ndjson` avec
  `event.dataset: openirn.operations` et `service.name: openirn-api` ;
- `logs-apache.access-*` et `logs-apache.error-*`, alimentés par
  l'intégration Apache ;
- `synthetics-http-*`, avec un moniteur HTTP portant
  `service.name: openirn-api` ;
- `metrics-system.cpu-*`, `metrics-system.memory-*` et
  `metrics-system.filesystem-*` ;
- `metrics-apache.status-*`, avec Apache `mod_status` accessible uniquement
  depuis l'Elastic Agent ;
- `metrics-linux.service-*`, avec le jeu de données `service` de l'intégration
  Linux pour les unités systemd ;
- `metrics-mysql.status-*`.

Les suffixes sont des jokers afin de ne dépendre d'aucun namespace Fleet. Les
métriques System et MySQL de l'instance doivent partager la même valeur ECS
`host.name`. Cette valeur est le seul paramètre obligatoire du rendu.

Vérifier les prérequis dans Dev Tools :

```text
FROM logs-openirn.api-*, logs-openirn.security-*, logs-openirn.operations-*,
     logs-apache.access-*, logs-apache.error-*, synthetics-http-*,
     metrics-system.cpu-*, metrics-system.memory-*,
     metrics-system.filesystem-*, metrics-apache.status-*,
     metrics-linux.service-*, metrics-mysql.status-*
| STATS documents = COUNT(*) BY data_stream = CONCAT(data_stream.type, "/", data_stream.dataset, "/", data_stream.namespace)
| SORT data_stream
```

Identifier ensuite la valeur `host.name` réellement reçue :

```text
FROM metrics-system.cpu-*
| STATS documents = COUNT(*) BY host.name
| SORT documents DESC
```

## Collecte Fleet à activer

Dans la politique de l'Elastic Agent installé sur le serveur OpenIRN, activer :

- l'intégration **System** avec les jeux de données CPU, mémoire et filesystem ;
- l'intégration **Apache** avec access logs, error logs et status ; son URL de
  statut doit viser `http://127.0.0.1:8092/server-status?auto` ;
- l'intégration **MySQL** avec le jeu de données status, configurée avec un
  compte MariaDB de supervision en lecture minimale ;
- l'intégration **Linux** avec le jeu de données service, limitée si possible à
  `openirn-api.service`, `openirn-api-backup.timer`, `apache2.service` et
  `mariadb.service` ;
- trois entrées Custom Logs pour `api-access.ndjson`, `security.ndjson` et
  `operations.ndjson`, dirigées respectivement vers les datasets
  `openirn.api`, `openirn.security` et `openirn.operations` ;
- un moniteur Synthetics HTTP vers le health public, avec
  `service.name: openirn-api` et la collecte TLS activée.

Les scripts de ce répertoire ne modifient pas Fleet : les noms de politiques,
les identifiants d'intégration et les credentials MariaDB dépendent de
l'infrastructure cible et ne doivent pas être versionnés. Vérifier chaque flux
avec la requête précédente avant de déployer le dashboard.

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
dashboard `OpenIRN — Supervision opérationnelle`. Ses 45 panneaux sont répartis
en six sections qui reprennent la matrice de supervision :

| Section | Indicateurs | Sources |
|---|---|---|
| Synthèse | disponibilité, état courant, requêtes/min, taux de 5xx, latence p95, âge de la dernière sauvegarde | Synthetics, Apache, OpenIRN |
| Usage | trafic par route, codes HTTP, clients et tenants actifs pseudonymisés, plateformes | Apache et journaux OpenIRN |
| Performance | latences p50/p95/p99, routes lentes, erreurs proxy, saturation Apache | journaux OpenIRN, Apache access/error et Apache Status |
| Sécurité | authentifications, rate limiting, enrôlements, révocations | audit OpenIRN |
| Infrastructure | CPU, mémoire, swap, disque, MariaDB, services systemd | intégrations System, MariaDB et Linux |
| Exploitation | sauvegardes, redémarrages, certificat TLS, version déployée | opérations OpenIRN et Synthetics |

Les champs d'usage sont initialisés avec une valeur vide afin que leur mapping
existe dès la première requête. Les compteurs de clients et de tenants ignorent
ces valeurs vides et utilisent uniquement les pseudonymes HMAC `device.id` et
`organization.id` ajoutés après une authentification réussie. La plateforme
provient du terminal enregistré par le serveur, pas du contenu libre d'un
en-tête client.

Le jeton
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

`openirn-alerting-rules.json` définit 19 règles ES|QL. Elles couvrent notamment
la disponibilité et l'absence de données, les 5xx et la latence, les événements
de sécurité, les ressources système et MariaDB, l'âge et les échecs de
sauvegarde, Apache, systemd, le swap, TLS et les redémarrages répétés. Le script
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
