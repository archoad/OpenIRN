# Patch 173.4 — Correctif BuildContext async dans la création de campagne

Ce patch corrige l’avertissement Flutter `use_build_context_synchronously` dans l’écran de gestion des campagnes.

La création d’une campagne charge d’abord l’inventaire SI de manière asynchrone, puis ouvre une boîte de dialogue. Le patch ajoute un contrôle `mounted` après ce chargement avant d’utiliser `context`, et vérifie aussi que l’écran est encore monté après la fermeture de la boîte de dialogue.

Aucun changement fonctionnel, serveur, base de données ou synchronisation.
