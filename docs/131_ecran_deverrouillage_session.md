# Patch 131 — Écran de déverrouillage de session

Ce patch clarifie le cycle d’accès OpenIRN avec le modèle server-only sans secret local persistant.

## Comportement cible

Au lancement de l’application :

1. **Terminal non enrôlé / révoqué**
   - seul le cartouche **Autoriser ce terminal** est affiché.

2. **Terminal enrôlé mais aucune session mémoire active**
   - seul le cartouche **Déverrouiller OpenIRN** est affiché ;
   - l’utilisateur sélectionne son profil ;
   - il saisit son code personnel ;
   - le serveur crée une session courte ;
   - le jeton de session reste uniquement en mémoire.

3. **Session serveur active**
   - les cartouches métier sont affichés ;
   - la session active est visible sur l’accueil ;
   - un bouton **Verrouiller** permet de supprimer la session mémoire.

## Changements

- L’accueil n’affiche plus les menus métier tant qu’aucune session serveur n’est active.
- L’administration ne redemande plus une authentification si une session active existe déjà : elle vérifie simplement que le profil actif est **Administrateur** ou **Pilote IRN**.
- La liste des campagnes reçoit directement l’utilisateur actif de la session serveur.
- L’ouverture d’une campagne ne redemande plus le profil et le code : elle utilise la session active.

## Données locales

Aucun secret n’est persisté localement. La session reste uniquement en mémoire via `AppSessionManager`.
