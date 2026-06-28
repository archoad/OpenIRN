# 111D — Nettoyage sécurité des terminaux autorisés

Ce patch finalise la première phase d'enrôlement des terminaux OpenIRN.

## Objectifs

- Ne plus présenter la saisie manuelle du bearer comme le fonctionnement normal.
- Afficher clairement l'identité et le mode d'autorisation du terminal courant.
- Distinguer les terminaux enrôlés avec un jeton individuel des anciens terminaux encore configurés avec le bearer historique.
- Préparer la révocation propre d'un terminal, y compris le terminal courant.
- Conserver une procédure d'urgence pour migration ou dépannage serveur.

## Changements côté interface

### Synchronisation API

La page `Synchronisation API` affiche désormais un cartouche `Terminal courant` avec :

- l'identifiant du terminal ;
- le tenant ;
- l'état de la synchronisation ;
- le mode d'autorisation :
  - `Jeton terminal` ;
  - `Bearer de transition` ;
  - `Non autorisé`.

La saisie du bearer n'est plus visible dans l'interface standard. Elle est déplacée dans une section repliée :

```text
Procédure d'urgence bearer
```

Cette section est à utiliser uniquement pour :

- migrer un ancien terminal ;
- récupérer un environnement de test ;
- dépanner un serveur dont l'enrôlement n'est pas encore disponible.

### Terminaux autorisés

La page `Administration → Terminaux autorisés` indique maintenant le terminal courant avec un badge :

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

5. Le terminal reçoit son propre jeton individuel.

## Procédure d'urgence

La saisie manuelle du bearer reste disponible uniquement dans :

```text
Synchronisation API → Configuration API → Procédure d'urgence bearer
```

Elle ne doit pas être utilisée pour autoriser des utilisateurs finaux. Le bearer global reste une clé de transition ou de récupération.

## Recommandation suivante

Le patch suivant recommandé est une phase de durcissement :

- stockage du jeton avec un stockage sécurisé natif quand disponible ;
- rotation des jetons ;
- expiration automatique des terminaux inactifs ;
- audit visible des opérations d'enrôlement/révocation.
