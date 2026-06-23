# Notice — OpenIRN et référentiel IRN

OpenIRN est une application indépendante destinée à faciliter l’exploration et l’évaluation locale de l’Indice de Résilience Numérique.

## Code OpenIRN

Le code source OpenIRN est distribué sous licence MIT, sauf mention contraire dans un fichier spécifique.

## Référentiel IRN officiel

Le référentiel IRN officiel est publié par l’aDRI / Digital Resilience Initiative et reste soumis à sa propre licence Creative Commons.

OpenIRN ne revendique aucun droit sur le référentiel officiel IRN.

Afin de permettre un fonctionnement hors ligne et des builds reproductibles, OpenIRN embarque un bundle JSON runtime du référentiel officiel dans les assets Flutter :

```text
flutter/assets/referentials/adri_irn_v1_1.json
flutter/assets/referentials/manifest.json
```

Ce bundle conserve les informations d’attribution : source officielle, version, fichier source, licence déclarée et checksum SHA-256.

Les fichiers de travail utilisés pour produire ce bundle ne sont pas versionnés dans le dépôt : fichier Excel/ODS officiel téléchargé, JSON canonique intermédiaire et rapports de validation.

## Données de campagne

Les campagnes créées dans OpenIRN, leurs réponses, justifications, exports JSON et journaux d’activité sont des données utilisateur. Elles ne sont pas couvertes par la licence du référentiel officiel.

## Attribution dans l’application

OpenIRN affiche une page “À propos” contenant :

- la source du référentiel ;
- la version utilisée ;
- le nom du fichier importé ;
- le checksum SHA-256 ;
- la licence déclarée ;
- les avertissements d’import éventuels.
