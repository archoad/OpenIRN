# Patch 023 — Import JSON local

Ce patch ajoute l'import local d'une campagne OpenIRN exportée en JSON.

## Objectif

Jusqu'ici, OpenIRN savait exporter une campagne locale avec :

- le référentiel ;
- la campagne ;
- les réponses R / NR / N.C. ;
- les justifications ;
- les scores ;
- le journal d'activité local.

Le patch ajoute l'opération inverse : coller un export JSON OpenIRN et créer une nouvelle campagne locale.

## Parcours utilisateur

```text
Campagnes locales
 → Importer JSON
 → Coller le JSON
 → Importer
 → Retour aux campagnes
```

## Contrôles réalisés à l'import

L'import vérifie notamment :

- que le JSON possède une `schemaVersion` OpenIRN valide ;
- que le type est `openirn.localAssessmentExport` ;
- que le référentiel ciblé correspond au référentiel actuellement chargé ;
- que le checksum du référentiel correspond, lorsqu'il est disponible des deux côtés ;
- que les critères importés existent bien dans le référentiel actif.

Les critères inconnus sont ignorés avec avertissement.

## Données importées

L'import crée une nouvelle campagne locale avec :

- un nouvel identifiant local ;
- le nom de la campagne source complété par un suffixe d'import ;
- le statut de campagne exporté ;
- les réponses et justifications ;
- le journal d'activité, rattaché à la nouvelle campagne ;
- un évènement local `Campagne importée`.

## Limites volontaires

L'import se fait encore par collage texte / presse-papiers. Il n'y a pas encore :

- d'ouverture de fichier `.json` ;
- de synchronisation API ;
- de résolution de conflit ;
- de fusion avec une campagne existante.

Ces limites sont volontaires : ce patch valide le contrat JSON avant d'ajouter un stockage plus avancé ou un serveur de synchronisation.
