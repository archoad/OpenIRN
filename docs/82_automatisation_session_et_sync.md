# Patch 082 — sessions déclenchées à l’ouverture et synchronisation simplifiée

Ce patch termine le recentrage de l’interface autour de l’automatisation.

## Campagnes locales

La page `Campagnes locales` ne présente plus de session active et ne contient plus de menu d’actions. Elle sert uniquement de point d’entrée vers les campagnes.

L’authentification utilisateur se fait au clic sur `Ouvrir` : l’identité et le rôle sélectionnés déterminent ensuite les menus visibles dans la campagne ouverte.

## Campagne ouverte

Une fois authentifié, le menu de la campagne contient maintenant :

- `Synchronisation`, visible pour tous les profils ;
- `Utilisateurs`, visible uniquement pour `Administrateur` et `Pilote IRN` ;
- `Export JSON`, `Journal` et `Réinitialiser`, toujours réservés à `Administrateur` et `Pilote IRN`.

Les évaluateurs ne voient que les critères qui leur sont affectés. Les cartes de critères sont contraintes à pleine largeur pour éviter les largeurs variables dans l’affichage campagne.

## Synchronisation

Pour les profils standards, la page `Synchronisation API` devient informative : état du serveur, dernier snapshot, fraîcheur locale et état détaillé de connexion. Le bouton `Synchroniser maintenant` disparaît de leur interface, car la synchronisation est automatique.

Pour `Administrateur` et `Pilote IRN`, la configuration serveur et les outils d’administration restent disponibles.
