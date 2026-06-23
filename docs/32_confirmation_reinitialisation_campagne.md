# Patch 030 — Confirmation avant réinitialisation de campagne

Ce patch ajoute une fenêtre de confirmation avant la réinitialisation des réponses d'une campagne locale.

## Nouveau comportement

Sur une campagne en cours :

1. l'utilisateur clique sur `Réinitialiser` ;
2. OpenIRN affiche une boîte de dialogue `Réinitialiser la campagne ?` ;
3. l'utilisateur doit confirmer explicitement ;
4. les réponses et justifications ne sont supprimées que si la confirmation est validée.

## Protection ajoutée

La réinitialisation est annulée si :

- la campagne est en lecture seule ;
- aucune réponse n'est saisie ;
- l'utilisateur clique sur `Annuler` ;
- l'utilisateur ferme la fenêtre de confirmation.

Le journal d'activité continue d'enregistrer l'évènement `Réponses réinitialisées` uniquement lorsque la suppression est réellement effectuée.
