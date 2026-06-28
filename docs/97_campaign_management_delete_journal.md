# Gestion des campagnes et suppression propre

La page `Campagnes` ne porte toujours pas de session active. L’action `Gérer les campagnes` déclenche une authentification ponctuelle avec un profil `Administrateur` ou `Pilote IRN`.

La suppression d’une campagne supprime les données de la campagne sur le terminal : campagne, réponses, affectations et journal d’activité. Le snapshot complet publié après suppression permet au backend SQLite de déduire que la campagne supprimée ne fait plus partie de l’état courant du tenant.

Le backend conserve le modèle `last_write_wins`, mais ajoute une règle de convergence : une campagne absente d’un snapshot complet est supprimée de `campaign_states`, `campaign_revisions` et des événements serveur associés. Les autres terminaux reçoivent ensuite un événement SSE et appliquent le snapshot de remplacement.
