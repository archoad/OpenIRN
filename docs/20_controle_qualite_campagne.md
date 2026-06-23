# Patch 018 — Contrôle qualité de campagne

Ce patch ajoute une vue de contrôle qualité pour une campagne locale OpenIRN.

## Objectif

Avant de partager un export JSON ou de préparer une future synchronisation API, l’application doit pouvoir signaler :

- les critères encore non cotés (`N.C.`) ;
- les réponses `R` ou `NR` sans justification ;
- le niveau de complétude de la campagne.

## Règles appliquées

- Un critère actif non coté est considéré comme incomplet.
- Une réponse `R` ou `NR` doit avoir une justification non vide.
- Les critères inactifs du référentiel sont ignorés.
- Une campagne est « prête pour revue » si tous les critères actifs sont cotés et toutes les réponses cotées sont justifiées.

## Écran ajouté

Depuis l’écran d’évaluation d’une campagne locale, un bouton `Qualité` ouvre :

- une carte de statut global ;
- une progression des critères cotés ;
- une progression des justifications ;
- la liste des critères non cotés ;
- la liste des réponses cotées sans justification.

Cette étape prépare les futurs workflows de validation, d’audit trail et de synchronisation serveur.
