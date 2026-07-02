# Patch 142A — Correctifs tenants : retour enrôlement et référentiel officiel

## Objectif

Ce patch corrige deux régressions observées après l’introduction de la gestion des tenants :

1. lorsqu’un tenant est sélectionné mais que le terminal n’est pas encore autorisé pour ce tenant, l’écran d’appairage doit permettre de revenir à l’ouverture de session ;
2. le chargement du référentiel officiel d’un tenant existant ne doit plus échouer avec une erreur serveur 500.

## Correctifs Flutter

- `DeviceEnrollmentScreen` accepte maintenant un `initialTenantId`.
- L’écran d’appairage préremplit le tenant actif au lieu de repartir systématiquement sur `default`.
- Un retour explicite **Retour ouverture session** est affiché dans l’écran d’appairage lorsque la route peut être dépilée.
- Le bouton d’appairage reste inchangé pour les cas normaux.

## Correctifs serveur

- Restauration de la constante `OPENIRN_RNR_SCORING_METADATA`, utilisée par les endpoints de référentiel officiel.
- Restauration des helpers d’import aDRI utilisés par `/referential/official/update`.
- Ajout d’un seeding automatique du référentiel officiel depuis le tenant `default` vers un tenant qui n’a pas encore de référentiel actif.

## Comportement attendu

- `default` reste permanent.
- Les utilisateurs, campagnes, sessions et terminaux restent isolés par tenant.
- Le référentiel officiel peut être copié comme socle de lecture d’un tenant vers un autre, sans copier les campagnes ni les utilisateurs métier.
- Un tenant nouvellement créé reçoit automatiquement une copie locale du référentiel officiel actif du tenant créateur, lorsque celui-ci existe.
- Un tenant existant sans référentiel actif est réparé automatiquement au prochain accès `/referential/official/current`, si `default` dispose d’un référentiel actif.
