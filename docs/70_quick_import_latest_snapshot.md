# Import rapide du dernier snapshot

Le bouton **Importer le dernier** simplifie le flux de synchronisation client.

Avant :

1. Statut serveur
2. Récupérer
3. Trouver le dernier snapshot
4. Importer
5. Confirmer

Après :

1. Importer le dernier
2. Confirmer

Le bouton appelle `/sync/pull` avec `limit=1`, affiche le résultat dans la carte des snapshots distants, puis réutilise le même mécanisme d'import contrôlé que l'import manuel.

Cette étape ne modifie pas encore le serveur et ne met pas en place de fusion intelligente : les campagnes importées restent des copies locales non destructrices.
