# Patch 141 — Indicateurs IRN : UX avancée

## Objectif

Améliorer le bloc **Indicateurs IRN** de la page **Synthèse** pour se rapprocher davantage de la slide de présentation fournie :

- afficher uniquement le **thème** de chaque pilier dans les tuiles, sans répéter le mot « Résilience » ;
- ajouter une **icône métier** sur chaque tuile ;
- conserver la tuile **Score global** alignée sur la hauteur des deux lignes de piliers ;
- ajouter une **légende** en bas du bloc pour expliquer la couleur des notes.

## Détails UX

Les libellés de tuiles sont simplifiés uniquement à l’affichage :

- `Résilience stratégique` devient `Stratégique` ;
- `Résilience Data & IA` devient `Data & IA` ;
- `Sécurité & Résilience` devient `Sécurité`.

Les libellés officiels complets du référentiel ne sont pas modifiés.

## Icônes par pilier

- `RES-1` : stratégie ;
- `RES-2` : économie / juridique ;
- `RES-3` : data ;
- `RES-4` : opérations ;
- `RES-5` : supply-chain ;
- `RES-6` : technologie ;
- `RES-7` : sécurité ;
- `RES-8` : environnement.

## Légende

La légende utilise la même fonction couleur que les tuiles :

- `0–39` : Faible ;
- `40–59` : À renforcer ;
- `60–79` : Solide ;
- `80–100` : Élevé ;
- `—` : Non coté.

## Impact

Patch Flutter uniquement. Aucun changement côté API, base SQLite, référentiel ou moteur de scoring.
