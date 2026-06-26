# Patch 048 — droits de saisie par critère affecté

Ce patch verrouille la saisie des évaluations au niveau du critère.

## Règles appliquées

- Administrateur : peut modifier tous les critères d'une campagne en brouillon.
- Pilote IRN : peut modifier tous les critères d'une campagne en brouillon.
- Évaluateur : peut modifier uniquement les critères qui lui sont explicitement affectés.
- Validateur : lecture seule sur les critères.
- Lecteur : lecture seule sur les critères.
- Campagne validée ou archivée : lecture seule pour tous les rôles.

## Effets UX

L'écran d'évaluation affiche la session active et le rôle. Les critères non modifiables affichent une raison explicite : lecture seule, critère non affecté au profil, critère affecté à un autre évaluateur, etc.

## Tests

Le patch ajoute `access_policy_service_test.dart` pour figer les règles d'accès métier.
