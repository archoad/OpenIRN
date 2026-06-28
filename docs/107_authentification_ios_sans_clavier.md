# Patch 107 — Authentification iOS sans clavier natif

Ce patch contourne le warning UIKit `TUIKeyplane.right.width == -1.5` observé sur smartphone iOS lors de l’ouverture d’une action administrateur depuis le menu `⋮` de la page **Campagnes**.

## Changement

Sur iPhone / écran compact iOS, la boîte de dialogue d’authentification Administrateur / Pilote IRN n’ouvre plus de `TextField` pour le code personnel.

Elle utilise désormais un pavé numérique Flutter interne :

- aucun clavier natif iOS n’est ouvert ;
- le code est masqué par des pastilles ;
- les actions `Effacer`, `Supprimer` et `Ouvrir` restent disponibles ;
- le comportement desktop/tablette reste inchangé avec le champ texte classique.

## Fichier modifié

- `flutter/lib/presentation/campaigns/campaign_list_screen.dart`

## Test attendu

Depuis un smartphone :

1. ouvrir la page **Campagnes** ;
2. ouvrir le menu `⋮` ;
3. choisir **Maintenance serveur**, **Gérer les campagnes** ou **Utilisateurs** ;
4. sélectionner un profil Administrateur ou Pilote IRN ;
5. saisir le code avec le pavé numérique intégré.

Le warning iOS lié à `TUIKeyplane` ne doit plus être déclenché par cette authentification, puisque le clavier natif n’est plus sollicité.
