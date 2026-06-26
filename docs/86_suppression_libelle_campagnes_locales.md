# Patch 086 — Suppression du libellé “campagnes locales”

Ce patch clarifie l’interface : les campagnes sont désormais présentées comme des campagnes OpenIRN synchronisées, et non comme des “campagnes locales”.

Le stockage sur le terminal reste conservé techniquement pour :

- le cache hors ligne ;
- la continuité en cas d’indisponibilité serveur ;
- la synchronisation automatique / SSE ;
- la reprise après fermeture de l’application.

L’objectif est seulement de ne plus exposer cette notion technique dans l’interface utilisateur.
