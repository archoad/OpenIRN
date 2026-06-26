# Administration des codes utilisateurs

Le patch 081 ajoute l’administration des codes personnels dans OpenIRN.

## Accès

La page `Utilisateurs` reste réservée aux profils :

- Administrateur ;
- Pilote IRN.

Depuis cette page, chaque utilisateur dispose d’une action `Code` lorsque la base centrale est disponible.

## Modification d’un code

L’administrateur ou le pilote IRN saisit :

- un nouveau code ;
- une confirmation du code.

OpenIRN appelle ensuite :

```http
POST /users/pin
Authorization: Bearer <token>
Content-Type: application/json
```

avec :

```json
{
  "tenantId": "archoad",
  "userId": "...",
  "pin": "..."
}
```

Le code n’est jamais stocké localement dans l’application. Il est envoyé au serveur, qui le hache avec PBKDF2-SHA256.

## Mode dégradé

Si l’API est indisponible, la page affiche la base locale mais désactive le bouton `Code`.
