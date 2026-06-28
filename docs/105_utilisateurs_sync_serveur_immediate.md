# Patch 105 — Utilisateurs : synchronisation serveur immédiate

Objectif : supprimer le fonctionnement « utilisateur local puis push différé » depuis la page **Utilisateurs**.

## Changements

- La page **Utilisateurs** charge la base utilisateurs depuis le serveur quand l’API est configurée.
- Les créations, modifications et suppressions passent désormais par `POST /users/replace` immédiatement.
- Le cache local `SharedPreferences` est seulement réaligné après acceptation du serveur.
- Si le serveur est indisponible ou si l’API n’est pas configurée, les actions de modification sont désactivées ou refusées.
- Après une modification acceptée par le serveur, OpenIRN publie immédiatement un snapshot pour réveiller les autres terminaux via la synchronisation globale.
- Les libellés utilisateur ne parlent plus d’ajout local ou de réalignement ultérieur.

## Fichiers modifiés

- `flutter/lib/data/api/openirn_api_client.dart`
- `flutter/lib/presentation/users/user_list_screen.dart`

## Test attendu

1. Ouvrir OpenIRN sur le Mac et le smartphone.
2. Aller dans **Campagnes → ⋮ → Utilisateurs** sur le Mac.
3. Créer ou modifier un utilisateur.
4. Vérifier que l’opération affiche une confirmation serveur immédiate.
5. Vérifier que le smartphone récupère la modification via la synchronisation globale.
