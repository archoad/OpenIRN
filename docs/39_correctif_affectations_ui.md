# Correctif UI — affectations des critères

Ce correctif améliore l'écran d'affectation des critères.

## Problèmes corrigés

- Le menu déroulant d'affectation pouvait provoquer un overflow horizontal sur certaines tailles de fenêtre ou avec des libellés utilisateur longs.
- Après l'affectation d'un utilisateur, le pilier en cours se repliait automatiquement à cause du rechargement de l'état local.

## Changements

- Le menu déroulant utilise maintenant `isExpanded: true` et tronque les libellés longs.
- La valeur `Non affecté` est sélectionnée explicitement lorsqu'aucun utilisateur n'est affecté.
- L'écran bascule automatiquement en disposition verticale sur les largeurs réduites.
- Les piliers dépliés sont conservés dans l'état de l'écran après une affectation.
