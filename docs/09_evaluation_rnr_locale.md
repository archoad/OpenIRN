# Patch 007 — Mini-évaluation officielle R / NR

Ce lot ajoute une première évaluation locale basée uniquement sur le référentiel officiel aDRI.

## Objectif

Valider le futur moteur de notation officiel sans encore introduire :

- les données entreprise ;
- les campagnes ;
- les utilisateurs ;
- le stockage local persistant ;
- la synchronisation API.

## Règle de calcul temporaire

Le score affiché est :

```text
score = R / (R + NR) × 100
```

Les critères `N.C.` / non cotés sont exclus du score mais comptent dans la complétude.

## Écrans ajoutés

Depuis l’écran d’accueil du référentiel, un bouton `Démarrer` ouvre une évaluation locale en mémoire.

L’écran affiche :

- score global ;
- nombre de critères cotés ;
- nombre de critères R ;
- nombre de critères NR ;
- nombre de critères N.C. ;
- score par pilier.

## Limite volontaire

Les réponses ne sont pas encore sauvegardées. Cette étape sert uniquement à valider l’ergonomie et le moteur de score officiel.
