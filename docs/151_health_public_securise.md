# Patch 151 — Health public sécurisé

## Objectif

Réduire les informations exposées par le endpoint public `/health` avant la publication v1.0.0.

L’ancien endpoint exposait notamment :

- la version détaillée de l’API ;
- le chemin de la base SQLite ;
- le mode d’authentification ;
- la liste des endpoints disponibles.

Ces informations sont utiles en diagnostic, mais trop bavardes pour un endpoint public.

## Nouveau comportement

`GET /health` renvoie maintenant uniquement un état opérationnel synthétique, inspiré d’un endpoint de supervision :

```json
{
  "cluster_name": "openirn-api",
  "status": "green",
  "timed_out": false,
  "number_of_nodes": 1,
  "number_of_data_nodes": 1,
  "active_primary_services": 1,
  "active_services": 1,
  "relocating_services": 0,
  "initializing_services": 0,
  "unavailable_services": 0,
  "unavailable_primary_services": 0,
  "delayed_unavailable_services": 0,
  "number_of_pending_tasks": 0,
  "number_of_in_flight_fetch": 0,
  "task_max_waiting_in_queue_millis": 0,
  "active_services_percent_as_number": 100.0
}
```

## Statuts

- `green` : base présente et contrôle d’intégrité SQLite OK ;
- `yellow` : base non encore initialisée ;
- `red` : contrôle d’intégrité impossible ou base en erreur.

## Sécurité

Le endpoint ne révèle plus :

- le chemin de la base ;
- les routes API ;
- les tenants ;
- les utilisateurs ;
- les campagnes ;
- les modes d’authentification internes.

Les diagnostics détaillés restent dans les endpoints de maintenance authentifiés.

## Option

Le nom logique affiché peut être personnalisé côté serveur avec :

```bash
OPENIRN_API_HEALTH_CLUSTER_NAME=archoad-openirn
```
