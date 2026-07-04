# 111D — Nettoyage sécurité des terminaux autorisés

Ce patch finalisait la première phase d'enrôlement des terminaux OpenIRN.

## Objectifs

- Ne plus présenter la saisie manuelle d’un secret global comme le fonctionnement normal.
- Afficher clairement l'identité et le mode d'autorisation du terminal courant.
- Distinguer les terminaux enrôlés avec un jeton individuel des sessions serveur courtes.
- Préparer la révocation propre d'un terminal, y compris le terminal courant.
- Conserver une compatibilité limitée pour migration ou dépannage serveur.

## Changements côté interface

### Synchronisation API

La page `Synchronisation API` affiche un cartouche `Terminal courant` avec :

- l'identifiant du terminal ;
- l’espace de travail ;
- l'état de la synchronisation ;
- le mode d'autorisation :
  - `Session serveur` ;
  - `Jeton terminal serveur` ;
  - `Jeton legacy en mémoire` ;
  - `Non autorisé`.

Depuis le patch 163B, le secret global historique n’est plus un mode d’administration. Les opérations sensibles reposent sur une session serveur courte associée à un rôle utilisateur.

### Terminaux autorisés

La page `Administration → Terminaux autorisés` indique le terminal courant avec un badge :

```text
Ce terminal
```

Si l'administrateur révoque le terminal courant, OpenIRN supprime aussi l'autorisation locale et arrête la synchronisation de fond. Le terminal devra ensuite être réappairé avec un nouveau code d'enrôlement.

## Procédure normale pour un nouveau terminal

1. Depuis un terminal déjà autorisé :

```text
Administration → Terminaux autorisés → Autoriser un nouveau terminal
```

2. Générer un code d'appairage court.

3. Sur le nouveau terminal :

```text
Autoriser ce terminal
```

4. Saisir le code d'appairage.

5. Le terminal reçoit son propre jeton individuel révocable.

## Recommandation suivante

- rotation des jetons ;
- expiration automatique des terminaux inactifs ;
- audit visible des opérations d'enrôlement/révocation.
