# Patch 041 — correctif export context multi-niveaux

Ce patch corrige une régression introduite lors de l'ajout des utilisateurs et affectations.

## Problème

`AssessmentExportScreen` initialisait `_exportContextFuture` avec `_loadExportContext()`, mais la méthode avait été supprimée du bon scope lors du correctif précédent.

Conséquences :

- `_loadExportContext` non défini dans `_AssessmentExportScreenState` ;
- repositories déclarés mais considérés inutilisés ;
- contexte export incomplet pour les utilisateurs et affectations.

## Correction

La méthode `_loadExportContext()` est réintroduite dans `_AssessmentExportScreenState` et charge :

- le journal d'activité local ;
- l'annuaire local ;
- les affectations de critères de la campagne.

Le test d'export est aussi nettoyé pour supprimer quelques `const` redondants.
