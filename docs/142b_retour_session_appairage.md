# Patch 142B — Retour ouverture session depuis l’appairage

## Objectif

Corriger l’expérience tenant lorsque l’utilisateur choisit un tenant sur lequel le terminal n’est pas encore autorisé.

Avant ce correctif, l’écran **Autoriser ce terminal** pouvait être affiché, mais le retour vers l’ouverture de session ne permettait pas de revenir proprement à un tenant déjà utilisable.

## Changements

- suppression du bouton de retour dans l’AppBar de l’écran d’appairage ;
- suppression du bouton de retour noyé dans les actions du formulaire ;
- ajout d’un cartouche dédié **Retour à l’ouverture de session** sous le cartouche d’appairage ;
- le retour :
  - abandonne l’appairage courant ;
  - revient au tenant permanent `default` ;
  - verrouille la session locale ;
  - force le rechargement de l’accueil après fermeture de l’écran d’appairage ;
- le rechargement est maintenant déclenché aussi lorsque l’écran d’appairage retourne `false`.

## Périmètre

Le patch ne modifie pas le serveur, le modèle tenant ni la politique d’autorisation. Il ne change pas non plus le processus d’appairage réussi.
