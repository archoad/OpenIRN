# Patch 126 — Nettoyage du menu de campagne et centralisation administration

Ce patch simplifie le menu `⋮` de la page d'une campagne maintenant que la synchronisation est automatique et que les opérations d'administration sont regroupées dans la page **Administration**.

## Changements

- Suppression de l'entrée **Synchronisation** du menu de campagne pour tous les profils.
- Suppression des entrées **Maintenance serveur** et **Historique / conflits** du menu de campagne.
- Les profils **Évaluateur**, **Validateur** et **Lecteur** ne conservent que :
  - **Synthèse** ;
  - **Qualité**.
- Les profils **Administrateur** et **Pilote IRN** conservent les actions métier utiles sur la campagne, comme les informations, affectations, export, journal et réinitialisation selon les droits existants.
- Ajout de **Historique / conflits** dans la page **Administration**.

## Résultat attendu

La page campagne reste centrée sur l'évaluation. Les fonctions transverses et serveur sont accessibles depuis :

```text
Accueil → Administration → Historique / conflits
```
