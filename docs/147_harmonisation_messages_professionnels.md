# Patch 147 — Harmonisation des messages professionnels

## Objectif

Rendre l’interface OpenIRN plus adaptée à un usage professionnel :

- suppression du tutoiement dans les messages visibles ;
- passage au vouvoiement ;
- remplacement de plusieurs termes techniques par des formulations plus compréhensibles ;
- clarification du vocabulaire multi-tenant côté interface.

## Principales évolutions

### Vouvoiement

Exemples :

- `ton profil` devient `votre profil` ;
- `saisis ton code personnel` devient `veuillez saisir votre code personnel` ;
- `réessaie` devient `veuillez réessayer` ;
- `crée` devient `créez` lorsque la phrase s’adresse à l’utilisateur.

### Vocabulaire plus accessible

Les messages destinés à l’utilisateur privilégient désormais :

- `espace de travail` au lieu de `tenant` ;
- `serveur OpenIRN` au lieu de `API` lorsque le détail technique n’est pas utile ;
- `clé d’accès` au lieu de `token API` ;
- `données serveur` ou `sauvegarde de synchronisation` au lieu de `snapshot`.

Les noms internes de variables et les routes API ne sont pas renommés.

## Périmètre

Le patch modifie uniquement les textes visibles et quelques messages d’erreur serveur. Il ne modifie pas :

- le modèle de données ;
- les rôles ;
- les règles d’autorisation ;
- les calculs IRN ;
- les endpoints API.
