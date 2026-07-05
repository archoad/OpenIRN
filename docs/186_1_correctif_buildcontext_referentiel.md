# Patch 186.1 — Correctif BuildContext async dans l’accueil/référentiel

Ce micro-correctif supprime les avertissements Flutter `use_build_context_synchronously` dans `referential_overview_screen.dart`.

Les libellés traduits utilisés comme raison de fermeture de session sont désormais calculés avant les appels asynchrones concernés, puis réutilisés après les `await` sans accéder à `context`.

Aucun changement fonctionnel, serveur ou base de données.
