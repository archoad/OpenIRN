# Patch 129 — Journal sécurité serveur

## Objectif

Ajouter une page d'administration pour consulter les événements de sécurité serveur maintenant qu'OpenIRN fonctionne sans secret persistant côté client.

## Fonctionnalités

- Nouvelle entrée `Journal sécurité` dans `Administration`.
- Consultation des événements issus de `device_audit_log` : enrôlements, invitations, révocations, sessions, limitations.
- Consultation des tentatives d'authentification issues de `auth_attempts` : succès, échecs et limitations anti-bruteforce.
- Filtres côté interface :
  - authentifications ;
  - terminaux / sessions ;
  - limite 50, 100, 200 ou 500 événements.

## API ajoutée

```text
GET /security/audit?tenantId=archoad&limit=100&includeAuthAttempts=true&includeDeviceAudit=true
```

L'endpoint exige une session serveur courte ou un bearer de transition. Il n'est pas accessible avec un simple terminal enrôlé sans authentification d'administration.

## Fichiers

```text
server/openirn-api/app/main.py
flutter/lib/domain/models/security_audit_event.dart
flutter/lib/data/api/openirn_api_client.dart
flutter/lib/presentation/admin/administration_screen.dart
flutter/lib/presentation/admin/security_audit_screen.dart
docs/129_journal_securite_serveur.md
```
