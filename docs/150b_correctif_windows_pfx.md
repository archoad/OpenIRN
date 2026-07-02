# Patch 150B — Correctif décodage certificat Windows

## Contexte

Le workflow de release signée Android / Windows échouait sur le job Windows lors de la création du fichier `openirn-windows-codesign.pfx` :

```text
Cannot process argument transformation on parameter 'Encoding'. 'Byte' is not a supported encoding name.
```

La cause vient de l'utilisation de `Set-Content -Encoding Byte`, syntaxe qui n'est plus compatible avec la version PowerShell disponible sur le runner GitHub Actions.

## Correction

Le workflow utilise maintenant l'API .NET :

```powershell
$certificateBytes = [System.Convert]::FromBase64String($env:WINDOWS_CERTIFICATE_BASE64)
[System.IO.File]::WriteAllBytes((Join-Path $PWD "openirn-windows-codesign.pfx"), $certificateBytes)
```

Cette méthode écrit directement le tableau d'octets décodé depuis le secret GitHub, sans passer par un encodage texte.

## Impact

- Aucun changement sur la signature Android.
- Aucun changement sur le certificat Windows.
- Aucun changement sur les artefacts produits.
- Le correctif concerne uniquement l'écriture du fichier `.pfx` dans le runner Windows.
