# Patch 142F — Cinématique d’ouverture de session tenant

## Objectif

Réduire les clics à l’ouverture d’OpenIRN tout en conservant le modèle multi-tenant.

## Nouveau comportement

- Si l’application ne connaît aucun tenant appairé, l’accueil affiche uniquement le cartouche **Choisir un tenant**.
- Si l’application connaît déjà un tenant appairé, l’accueil conserve ce tenant et affiche directement :
  - **Déverrouiller OpenIRN** ;
  - **Changer de tenant**.
- Si un tenant est choisi mais que le terminal n’est pas autorisé dans ce tenant, l’accueil affiche :
  - **Autoriser ce terminal** ;
  - **Retour au choix du tenant**.

## Détails techniques

Le patch ne réinitialise plus systématiquement le tenant au lancement. Il conserve le tenant public stocké localement, mais continue de vider la session applicative volatile.

Le changement de tenant depuis l’écran de déverrouillage ouvre directement la boîte de sélection des tenants, sans effacer le tenant courant tant qu’un nouveau tenant n’a pas été choisi.

## Sécurité

Aucune session utilisateur n’est conservée au démarrage. Seul le contexte public du terminal reste disponible : tenant sélectionné et identifiant terminal. L’accès aux campagnes, au référentiel et à l’administration reste conditionné à une session utilisateur courte.
