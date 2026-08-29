# Runbook des alertes OpenIRN

Ce runbook accompagne le dashboard Kibana
`OpenIRN — Santé API et sécurité` et les règles définies dans
`openirn-alerting-rules.json`.

Les règles écrivent leurs changements d'état dans le journal de Kibana avec les
préfixes `[OpenIRN][ALERTE]` et `[OpenIRN][RÉTABLI]`. Elles n'envoient ni
courriel, ni webhook, ni message vers un service externe.

## Contrôles communs

Définir les valeurs propres à l'instance dans le shell courant :

```bash
export OPENIRN_API_HOST=openirn-api.example.org
export OPENIRN_API_SSH_PORT=22
export OPENIRN_API_SSH_USER=root
export OPENIRN_API_PUBLIC_URL=https://openirn.example.org/api
```

Commencer par vérifier l'heure, l'état du serveur et le health public :

```bash
date --iso-8601=seconds
ssh -p "${OPENIRN_API_SSH_PORT}" "${OPENIRN_API_SSH_USER}@${OPENIRN_API_HOST}"
systemctl is-active openirn-api elastic-agent
curl --fail --silent --show-error --max-time 10 \
	http://127.0.0.1:8091/health | jq
exit
curl --fail --silent --show-error --max-time 20 \
	"${OPENIRN_API_PUBLIC_URL}/health" | jq
```

Dans Kibana, ouvrir **Stack Management → Rules**, filtrer sur le tag `OpenIRN`,
puis ouvrir la règle. Contrôler sa dernière exécution, son message, sa fenêtre
de temps et le dashboard associé avant toute modification.

Afficher les changements d'état sur l'hôte Kibana :

```bash
journalctl -u kibana --since '-30 minutes' --no-pager \
	| grep -F '[OpenIRN]'
```

## Disponibilité et collecte

| Règle | Condition | Première intervention |
|---|---|---|
| API indisponible | au moins 2 contrôles synthétiques en échec sur 3 min | vérifier le health public, Apache, puis `openirn-api` |
| Moniteur synthétique silencieux | aucune mesure sur 5 min, confirmée deux fois | vérifier l'agent et le moniteur sur `ia`, puis l'ingestion Synthetics |
| Journal d'accès API silencieux | aucun événement sur 5 min, confirmé deux fois | vérifier `openirn-api`, le fichier d'accès et Elastic Agent sur l'hôte API |

Pour une indisponibilité publique alors que le health local fonctionne :

```bash
ssh -p "${OPENIRN_API_SSH_PORT}" "${OPENIRN_API_SSH_USER}@${OPENIRN_API_HOST}"
systemctl is-active apache2 openirn-api
journalctl -u apache2 -u openirn-api --since '-15 minutes' --no-pager
ss -lntp | grep -E ':(443|8091)[[:space:]]'
```

Pour une perte d'ingestion, ne pas redémarrer immédiatement l'API. Vérifier
d'abord que les fichiers progressent et que l'agent est actif :

```bash
ssh -p "${OPENIRN_API_SSH_PORT}" "${OPENIRN_API_SSH_USER}@${OPENIRN_API_HOST}"
ls -lh /var/lib/openirn-api/logs/
tail -n 5 /var/lib/openirn-api/logs/api-access.ndjson | jq -c .
systemctl is-active elastic-agent
journalctl -u elastic-agent --since '-15 minutes' --no-pager
```

## Erreurs et latence API

| Règle | Condition | Première intervention |
|---|---|---|
| Rafale HTTP 5xx | au moins 3 réponses 5xx sur 5 min | identifier routes, traces et erreurs API corrélées |
| Latence p95 élevée | p95 au moins 500 ms sur 10 min, au moins 5 requêtes, confirmé deux fois | comparer CPU, mémoire, MariaDB et route lente |

Rechercher les erreurs récentes dans Discover avec le data stream
`logs-openirn.api-*`, ou utiliser ES|QL :

```text
FROM logs-openirn.api-*
| WHERE @timestamp >= NOW() - 15 minutes
| WHERE http.response.status_code >= 500
| KEEP @timestamp, trace.id, http.request.method, url.path,
       http.response.status_code, event.duration
| SORT @timestamp DESC
```

Ne pas rechercher de corps de requête ou de jeton : ces données ne doivent pas
être présentes dans le journal. Utiliser `trace.id` pour corréler une erreur
d'accès avec les journaux applicatifs.

## Sécurité

| Règle | Condition | Première intervention |
|---|---|---|
| Échecs répétés | au moins 10 échecs d'authentification, limitations ou refus par source pseudonymisée sur 5 min | vérifier action, motif, tenant et récurrence sans tenter de retrouver l'adresse brute |
| Sévérité haute | au moins un événement de sévérité 7 sur 5 min | traiter immédiatement une limitation, un blocage ou une saturation de capacité |

Requête de triage :

```text
FROM logs-openirn.security-*
| WHERE @timestamp >= NOW() - 30 minutes
| KEEP @timestamp, trace.id, event.action, event.outcome, event.severity,
       openirn.security.reason, openirn.security.source_address_hash
| SORT @timestamp DESC
```

Les identifiants et adresses sont pseudonymisés. Ne pas diminuer les protections
d'authentification pour faire disparaître une alerte. En cas d'abus confirmé,
conserver les traces, vérifier les réglages anti-abus et appliquer le blocage au
niveau du frontal ou du filtrage réseau selon la procédure d'exploitation.

## Ressources et MariaDB

| Règle | Condition | Première intervention |
|---|---|---|
| CPU élevé | moyenne au moins 85 % sur 10 min, confirmée deux fois | identifier les processus et vérifier la latence API |
| Mémoire élevée | moyenne au moins 90 % sur 10 min, confirmée deux fois | contrôler mémoire, swap et principaux consommateurs |
| Disque racine presque plein | occupation au moins 85 % | trouver la croissance sans supprimer de données à l'aveugle |
| Connexions MariaDB avortées | hausse d'au moins 5 sur 10 min | vérifier MariaDB, l'API et les erreurs de connexion |

Commandes de diagnostic non destructrices sur l'hôte API :

```bash
date --iso-8601=seconds
uptime
free -h
df -h /
ps -eo pid,comm,%cpu,%mem --sort=-%cpu | head -n 15
systemctl is-active mariadb openirn-api
journalctl -u mariadb -u openirn-api --since '-30 minutes' --no-pager
```

Avant tout nettoyage de disque, résoudre le chemin exact, mesurer son volume et
identifier sa politique de rétention. Ne jamais supprimer un data stream, une
sauvegarde MariaDB ou un journal OpenIRN uniquement pour faire repasser la jauge
sous le seuil.

## Rétablissement et ajustement

Une règle repasse automatiquement à l'état rétabli lorsque sa requête ne renvoie
plus de résultat. Vérifier le retour durable à la normale sur le dashboard avant
de clore l'incident.

Si un seuil doit être ajusté :

1. mesurer au moins sept jours représentatifs ;
2. modifier `openirn-alerting-rules.json` dans le dépôt ;
3. valider la requête ES|QL sur sa fenêtre réelle ;
4. relire le diff ;
5. redéployer avec `deploy-alerting-rules.sh`.

Éviter les changements uniquement dans l'interface Kibana : le prochain
déploiement remettrait la définition versionnée.
