# Patch 149 — Releases signées Android / Windows

## Objectif

Ce dépôt est actuellement configuré pour produire des releases signées sur :

- Android ;
- Windows.

macOS et iOS sont volontairement hors périmètre tant qu'aucun compte Apple Developer payant n'est disponible. Le projet Flutter macOS/iOS reste présent, mais les artefacts Apple ne sont pas publiés par le workflow de release courant.

Aucune clé privée, aucun certificat et aucun mot de passe ne doivent être stockés dans le dépôt Git. Tous les éléments sensibles doivent rester dans `secrets/`, ignoré par Git, puis être copiés dans les **secrets GitHub Actions**.

## Artefacts publiés

- `openirn-android.apk` : APK Android signé.
- `openirn-android.aab` : Android App Bundle signé pour Google Play.
- `openirn-windows-signed.zip` : application Windows avec binaires signés.
- `SHA256SUMS.txt` : empreintes SHA-256.

## Secrets GitHub Actions nécessaires

### Android

| Secret | Description |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | Keystore Android encodé en base64. |
| `ANDROID_KEYSTORE_PASSWORD` | Mot de passe du keystore. |
| `ANDROID_KEY_PASSWORD` | Mot de passe de la clé. |
| `ANDROID_KEY_ALIAS` | Alias de la clé, par exemple `openirn-upload`. |

Création locale depuis le répertoire OpenIRN :

```bash
base64 -i secrets/android/openirn-upload-keystore.jks \
  -o secrets/github/ANDROID_KEYSTORE_BASE64.txt
```

### Windows

| Secret | Description |
| --- | --- |
| `WINDOWS_CERTIFICATE_BASE64` | Certificat Windows `.pfx` encodé en base64. |
| `WINDOWS_CERTIFICATE_PASSWORD` | Mot de passe du `.pfx`. |

Création locale depuis le répertoire OpenIRN :

```bash
base64 -i secrets/windows/openirn-windows-codesign.pfx \
  -o secrets/github/WINDOWS_CERTIFICATE_BASE64.txt
```

## Note sur le certificat Windows auto-signé

Un certificat Windows auto-signé valide la chaîne technique de signature, mais ne donne pas une confiance utilisateur équivalente à un certificat de signature de code reconnu. Pour une distribution publique, il faudra passer à un certificat OV/EV ou à un service de signature reconnu.

## Lancer une release signée

Par tag Git :

```bash
git tag v0.6.1
git push origin v0.6.1
```

Manuellement :

1. ouvrez **Actions** ;
2. choisissez **Release signée Android / Windows** ;
3. cliquez **Run workflow** ;
4. indiquez le tag, par exemple `v0.6.1` ;
5. laissez `prerelease=false` pour une vraie release.

## Validation locale

```bash
./tools/check_openirn_release_preflight.sh --tag v0.6.1
./tools/check_openirn_release_preflight.sh --tag v0.6.1 --require-secrets
```

La seconde commande vérifie les variables d'environnement si vous les avez exportées localement. Elle ne lit jamais le contenu des secrets.
