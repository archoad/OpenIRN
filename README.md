# OpenIRN

OpenIRN est une application open source destinée à conduire des campagnes d’évaluation de l’Indice de Résilience Numérique (IRN), avec une API serveur pour centraliser le référentiel officiel, les campagnes, les utilisateurs, les terminaux et les opérations d’administration.

## Fonctionnalités principales

- consultation du référentiel IRN officiel ;
- création et gestion de campagnes d’évaluation ;
- cotation des critères en `R / NR / N.C.` ;
- justification des réponses ;
- workflow de campagne et journal d’activité ;
- gestion des utilisateurs, rôles et sessions ;
- enrôlement et autorisation des terminaux ;
- synchronisation via API ;
- administration du référentiel officiel ;
- sauvegardes serveur sécurisées avec manifeste signé.

## Architecture du dépôt

```text
OpenIRN/
├── api/                 # contrats API
├── docs/                # documentation projet et journal des patchs
├── flutter/             # application Flutter multi-plateforme
├── schemas/             # schémas JSON
├── server/              # API OpenIRN et scripts serveur
├── tools/               # outils de maintenance projet
├── README.md
├── LICENSE
├── NOTICE.md
├── CONTRIBUTING.md
├── SECURITY.md
└── CODE_OF_CONDUCT.md
```

## Référentiel IRN officiel

Le code de OpenIRN est distinct du référentiel IRN officiel.

Le référentiel IRN est publié par l’aDRI / Digital Resilience Initiative sous sa propre licence Creative Commons.

## Licence du code

Le code OpenIRN est proposé sous licence MIT. Voir [`LICENSE`](LICENSE).

Cette licence ne couvre pas le référentiel officiel IRN, qui reste soumis à sa propre licence et à ses propres conditions d’utilisation.
