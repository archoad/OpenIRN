# Patch 046 — Conservation réelle de la position dans l’écran Affectations

Le patch 045 mémorisait la position de scroll avant rechargement, mais l’écran repassait brièvement par un état de chargement, ce qui pouvait reconstruire la liste et revenir en tête.

Ce patch corrige le comportement en mettant à jour localement l’état des affectations après chaque modification, sans recharger toute la page.

## Comportement attendu

- le pilier ouvert reste ouvert ;
- la position de scroll ne remonte plus en tête de liste ;
- le menu déroulant affiche immédiatement la nouvelle affectation ;
- la sauvegarde locale et le journal d’activité restent inchangés.
