# Patch 167 — Terminaux uniques multi-espaces

## Objectif

Un même terminal peut être autorisé dans plusieurs espaces de travail OpenIRN. La vue d'administration ne doit plus le présenter comme plusieurs terminaux indépendants lorsque l'administrateur affiche tous les espaces : le terminal est identifié par un `device_id` stable et expose la liste des espaces dans lesquels il est enrôlé.

## Changements serveur

- `/devices/enrollment/consume` accepte maintenant un champ optionnel `deviceId`.
- Lorsqu'un terminal déjà connu s'enrôle dans un nouvel espace, le serveur réutilise cet identifiant au lieu de générer un nouvel identifiant serveur.
- Un ré-enrôlement dans le même espace réactive/met à jour l'autorisation existante au lieu de créer une entrée concurrente.
- La réponse `/devices?allTenants=true` regroupe les entrées par `deviceId` et ajoute :
  - `tenantIds`
  - `tenantLabels`
  - `tenantCount`
  - `tenants[]`, avec le détail par espace.
- Un index MariaDB `idx_authorized_devices_device_identity` accélère la vue globale par terminal.

## Changements Flutter

- L'écran d'enrôlement envoie l'identifiant local stable du terminal au serveur.
- L'écran d'administration des terminaux affiche un seul terminal avec plusieurs badges d'espaces lorsque la vue globale est activée.
- La carte terminal affiche l'identifiant technique du terminal pour faciliter l'audit et les corrections manuelles.

## Note sur l'historique

Les anciens enrôlements créés avant ce patch peuvent avoir des identifiants différents pour un même terminal physique, car le serveur générait auparavant un nouvel identifiant à chaque consommation de code. Le patch garantit l'unicité pour les nouveaux enrôlements. Les anciens doublons peuvent être corrigés au cas par cas en ré-enrôlant le terminal dans les espaces concernés puis en révoquant les anciennes entrées.
