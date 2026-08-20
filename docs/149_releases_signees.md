# Patch 149 — Releases signées Android / Windows

## Objectif

OpenIRN produit actuellement des releases signées pour :

- Android ;
- Windows.

macOS et iOS restent volontairement hors périmètre tant que la chaîne Apple Developer / notarisation n'est pas activée.

La chaîne Windows de production n'utilise plus de certificat `.pfx` exporté. La signature est réalisée par **Microsoft Azure Artifact Signing** avec un profil **Public Trust**, depuis GitHub Actions, au moyen d'une authentification **OpenID Connect (OIDC)** auprès de Microsoft Entra.

Aucune clé privée de signature Windows n'est exportée ni stockée dans le dépôt ou dans les secrets GitHub.

## Artefacts publiés

Le workflow `.github/workflows/release.yml` publie :

- `openirn-android.apk` : APK Android signé ;
- `openirn-android.aab` : Android App Bundle signé ;
- `openirn-windows-signed.zip` : distribution Windows portable contenant `OpenIRN.exe` signé ;
- `openirn-windows-x64.msix` : package MSIX x64 signé et horodaté ;
- `SHA256SUMS.txt` : empreintes SHA-256 des artefacts publiés.

## Signature Android

La signature Android continue d'utiliser les secrets GitHub Actions suivants :

| Secret | Description |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | Keystore Android encodé en base64. |
| `ANDROID_KEYSTORE_PASSWORD` | Mot de passe du keystore. |
| `ANDROID_KEY_PASSWORD` | Mot de passe de la clé. |
| `ANDROID_KEY_ALIAS` | Alias de la clé, par exemple `openirn-upload`. |

Création locale du secret base64 :

```bash
base64 -i secrets/android/openirn-upload-keystore.jks \
  -o secrets/github/ANDROID_KEYSTORE_BASE64.txt
```

Les fichiers de signature Android restent locaux dans `secrets/`, répertoire ignoré par Git.

## Signature Windows avec Azure Artifact Signing

### Ressources Azure

La chaîne de signature Windows utilise :

| Élément | Valeur |
| --- | --- |
| Service | Azure Artifact Signing |
| Compte Artifact Signing | `openirnsign` |
| Profil de certificat | `openirn-public` |
| Type de profil | `PublicTrust` |
| Région | North Europe |
| Endpoint | `https://neu.codesigning.azure.net/` |
| Identité éditeur | `Archoad` |

Le sujet du certificat validé est :

```text
CN=Archoad, O=Archoad, L=Noyen-sur-Sarthe, S=Sarthe, C=FR
```

Les certificats Artifact Signing sont gérés et renouvelés automatiquement par Microsoft. Le workflow ne référence donc aucun thumbprint fixe.

### Authentification GitHub Actions → Microsoft Entra

La connexion à Azure se fait avec OIDC. Aucun `AZURE_CLIENT_SECRET` n'est nécessaire.

Les trois secrets GitHub Actions utilisés sont :

| Secret | Description |
| --- | --- |
| `AZURE_CLIENT_ID` | Application Entra utilisée par GitHub Actions. |
| `AZURE_TENANT_ID` | Tenant Microsoft Entra Archoad. |
| `AZURE_SUBSCRIPTION_ID` | Souscription Azure contenant `openirnsign`. |

Le job Windows utilise l'environnement GitHub :

```text
artifact-signing
```

Le credential fédéré de production est associé au sujet OIDC :

```text
repo:archoad/OpenIRN:environment:artifact-signing
```

Un second credential peut être conservé pour les workflows de test exécutés depuis `main` :

```text
repo:archoad/OpenIRN:ref:refs/heads/main
```

L'application Entra utilisée par GitHub dispose uniquement du rôle nécessaire à la signature :

```text
Artifact Signing Certificate Profile Signer
```

sur le profil `openirn-public`.

## Chaîne Windows de production

Le job Windows de `.github/workflows/release.yml` exécute la séquence suivante :

1. checkout du tag de release ;
2. installation de Flutter et des dépendances ;
3. `flutter build windows --release` ;
4. authentification Azure via `azure/login` et OIDC ;
5. signature Authenticode de `OpenIRN.exe` avec `openirn/openirn-public` ;
6. vérification de la signature et du sujet du certificat ;
7. calcul de la version MSIX depuis `flutter/pubspec.yaml` ;
8. création d'un MSIX non signé ;
9. contrôle du `AppxManifest.xml` ;
10. signature du MSIX avec Azure Artifact Signing ;
11. horodatage RFC 3161 via le service Microsoft ;
12. vérification finale du MSIX avec SignTool ;
13. publication du ZIP Windows et du MSIX dans la GitHub Release.

Le timestamp utilisé est :

```text
http://timestamp.acs.microsoft.com
```

L'horodatage permet de conserver la validité de la signature après expiration du certificat court terme utilisé par Artifact Signing.

## Identité MSIX

Le package MSIX hors Microsoft Store utilise :

```text
Identity Name : Archoad.OpenIRN
Publisher     : CN=Archoad, O=Archoad, L=Noyen-sur-Sarthe, S=Sarthe, C=FR
Architecture  : x64
```

Le champ `Publisher` du manifeste doit rester strictement identique au sujet du certificat Artifact Signing.

La version MSIX est dérivée de la version Flutter. Par exemple :

```yaml
version: 1.3.1+42
```

devient :

```text
1.3.1.42
```

dans le manifeste MSIX.

## Ancien mécanisme PFX — supprimé

L'ancienne chaîne Windows utilisait :

```text
WINDOWS_CERTIFICATE_BASE64
WINDOWS_CERTIFICATE_PASSWORD
openirn-windows-codesign.pfx
```

Ces éléments ne sont plus utilisés par la chaîne de production et les deux anciens secrets GitHub peuvent être supprimés.

Le workflow ne doit plus :

- reconstruire un `.pfx` depuis un secret base64 ;
- importer une clé privée Windows ;
- transmettre un mot de passe PFX à SignTool ;
- utiliser `timestamp.digicert.com` pour cette chaîne.

Les motifs `*.pfx`, `*.p12`, `*.key`, etc. doivent néanmoins rester dans `.gitignore` comme protection générale contre une publication accidentelle de secrets.

Les scripts de contrôle conservent volontairement les noms de l'ancienne chaîne uniquement afin de détecter toute réintroduction accidentelle du mécanisme PFX.

## Contrôles avant release

Contrôle de la configuration de signature :

```bash
./tools/check_release_signing_setup.sh
```

Préflight général :

```bash
./tools/check_openirn_release_preflight.sh --tag vX.Y.Z
```

Contrôle incluant l'existence des secrets GitHub :

```bash
./tools/check_openirn_release_preflight.sh \
  --tag vX.Y.Z \
  --require-secrets
```

Les scripts ne lisent ni n'affichent la valeur des secrets.

## Lancer une release

### Par tag Git

Après avoir aligné la version dans `flutter/pubspec.yaml` :

```bash
git tag vX.Y.Z
git push origin vX.Y.Z
```

Le workflow **Release signée Android / Windows** est déclenché automatiquement.

### Manuellement

Dans GitHub :

1. ouvrir **Actions** ;
2. sélectionner **Release signée Android / Windows** ;
3. cliquer sur **Run workflow** ;
4. fournir le tag à publier ;
5. choisir si la release doit être marquée comme pré-release.

Le workflow vérifie que le tag demandé correspond à la version publique du `pubspec.yaml`.

## Validation de la chaîne

La chaîne Azure Artifact Signing a été validée en production avec la release **OpenIRN v1.3.1**.

La vérification SignTool du MSIX doit se terminer par :

```text
Successfully verified
Number of warnings: 0
Number of errors: 0
```

Le certificat de signature doit présenter le sujet Archoad attendu et la signature doit être horodatée par l'autorité de timestamp Microsoft.

## Sécurité

La configuration actuelle réduit fortement l'exposition des secrets Windows :

- aucune clé privée Windows exportable dans GitHub ;
- aucun certificat PFX stocké dans GitHub Actions ;
- aucun mot de passe de certificat Windows ;
- authentification GitHub → Azure par jeton OIDC de courte durée ;
- rôle Azure limité au profil de signature ;
- environnement GitHub `artifact-signing` dédié aux releases ;
- contrôle automatique du Publisher MSIX avant signature ;
- vérification de la signature après création du package ;
- publication de `SHA256SUMS.txt`.

Les secrets Android restent nécessaires tant que la signature Android repose sur le keystore d'upload.

## macOS et iOS

Les artefacts macOS et iOS ne sont pas produits dans ce profil de release. Ils pourront être ajoutés ultérieurement lorsque les certificats Apple Developer et la notarisation seront disponibles.
