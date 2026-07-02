# Patch 150C — Validation du certificat Windows PFX

## Contexte

Le job Windows de GitHub Actions échouait avec :

```text
SignTool Error: The specified PFX password is not correct.
```

Le workflow décodait bien le secret `WINDOWS_CERTIFICATE_BASE64`, mais l'erreur n'était détectée qu'au moment de l'appel à `signtool.exe`.

## Correction

Le workflow valide maintenant le fichier `.pfx` juste après son décodage :

- ouverture du PFX avec `WINDOWS_CERTIFICATE_PASSWORD` ;
- vérification de la présence d'une clé privée ;
- affichage du sujet et de l'empreinte du certificat ;
- message d'erreur explicite si le mot de passe GitHub ne correspond pas au mot de passe d'export du `.pfx`.

Le mot de passe est aussi normalisé par `Trim()` pour éviter les erreurs dues à un retour ligne ou à un espace accidentel en début/fin de secret.

## Vérification locale recommandée

Sur macOS ou Linux :

```bash
openssl pkcs12 \
  -in secrets/windows/openirn-windows-codesign.pfx \
  -info -noout \
  -passin pass:'MOT_DE_PASSE_DU_PFX'
```

Si cette commande échoue, le mot de passe n'est pas celui du fichier PFX.

## Mise à jour du secret GitHub

Utiliser de préférence la saisie interactive pour éviter les problèmes de caractères spéciaux :

```bash
gh secret set WINDOWS_CERTIFICATE_PASSWORD
```

Puis coller le mot de passe exact du fichier `.pfx`.
