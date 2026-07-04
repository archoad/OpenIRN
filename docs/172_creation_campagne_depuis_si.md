# Patch 172 — Création d’une campagne depuis un SI

Ce patch introduit la création d’une campagne IRN à partir d’un système d’information existant dans l’inventaire SI.

## Principe

Lors de la création d’une campagne, le Pilote IRN peut choisir un système d’information existant. La campagne conserve alors dans ses métadonnées :

- la fonction critique associée ;
- le système d’information choisi ;
- la liste des actifs du SI au moment de la création de campagne.

La campagne devient une campagne de notation par actif : chaque actif du SI dispose de son propre jeu de réponses IRN.

## Interface

Dans la boîte de création d’une campagne :

- un champ permet de choisir le système d’information à évaluer ;
- le nom et la description de la campagne sont préremplis à partir du SI ;
- un aperçu indique la fonction critique, le porteur SI et le nombre d’actifs à noter ;
- un SI sans actif ne peut pas être utilisé pour créer une campagne de notation par actif.

Dans l’écran d’évaluation :

- un cartouche **Notation par actif** apparaît pour les campagnes créées depuis un SI ;
- le pilote ou l’évaluateur choisit l’actif en cours d’évaluation ;
- les réponses sont enregistrées séparément pour chaque actif ;
- les compteurs affichent la progression par actif.

## Stockage

Les réponses d’une campagne SI sont conservées dans le payload existant des campagnes, avec des clés de réponse au format :

```text
asset:<asset_id>:criterion:<criterion_id>
```

Ce choix évite une migration MariaDB supplémentaire à ce stade et reste compatible avec le mécanisme de synchronisation existant.

## Limites assumées

Ce patch ne rattache pas encore les exports de synthèse à une vue multi-actifs complète. L’écran d’évaluation, la synthèse et la qualité travaillent sur l’actif sélectionné. Une étape suivante pourra ajouter une synthèse consolidée par SI et par actif.
