# Patch 143 — Administrateur solution et accès transverse aux tenants

## Objectif

Introduire explicitement la notion d’**administrateur solution OpenIRN**.

Le tenant `archoad` devient le tenant d’administration solution par défaut. Tout utilisateur actif ayant le rôle `administrator` dans ce tenant peut administrer les autres tenants, y compris ceux qui n’ont encore aucun utilisateur local.

Le tenant source est configurable côté API avec :

```bash
OPENIRN_SOLUTION_ADMIN_TENANT_ID=archoad
```

## Règles conservées

- Les campagnes restent rattachées à un seul tenant.
- Les utilisateurs ordinaires restent rattachés à un seul tenant.
- Les Pilotes IRN, évaluateurs, validateurs et lecteurs ne deviennent pas transverses.
- Le rôle transverse ne s’applique qu’aux administrateurs actifs du tenant solution.

## Ce que le patch ajoute

### Côté API

- autorisation transverse pour les sessions administrateur du tenant solution ;
- `GET /tenants` expose `solutionAdministrator: true` lorsque le token courant correspond à un administrateur solution ;
- synchronisation de bootstrap des administrateurs solution actifs vers les tenants existants ;
- synchronisation des terminaux actifs du tenant solution vers les tenants existants afin de ne pas bloquer l’administration initiale ;
- verrouillage de session plus robuste lorsque l’administrateur solution administre un tenant différent de son tenant d’authentification.

### Côté Flutter

- la page **Tenants** affiche un badge `Administrateur solution` lorsque le serveur confirme ce statut ;
- le bouton devient **Administrer ce tenant** pour un administrateur solution ;
- l’administration d’un autre tenant conserve la session solution active ;
- la configuration publique peut pointer vers le tenant administré sans détruire la session courante.

## Modèle de sécurité

La session reste créée dans le tenant solution. Le serveur reconnaît ensuite le token de session et autorise les opérations administratives sur les autres tenants. Ce n’est donc pas un contournement côté client : l’autorisation transverse est contrôlée côté API.
