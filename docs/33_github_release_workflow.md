# GitHub Release workflow

Le workflow de release OpenIRN construit et publie les artefacts signés lorsqu’un tag `v*` est poussé ou lorsque le workflow est lancé manuellement depuis GitHub Actions.

## Workflow principal

Fichier :

```text
.github/workflows/release.yml
```

Nom GitHub Actions :

```text
Release signée
```

## Artefacts produits

- `openirn-android.apk` : APK Android signé.
- `openirn-android.aab` : Android App Bundle signé.
- `openirn-windows-signed.zip` : application Windows avec binaires signés.
- `openirn-macos-signed-notarized.zip` : application macOS signée Developer ID et notarizée.
- `openirn-ios.ipa` : IPA iOS signé.
- `SHA256SUMS.txt` : empreintes SHA-256 des artefacts.

## Créer une release

```bash
git tag v0.6.1
git push origin v0.6.1
```

Par défaut, un tag `v*` crée une vraie release GitHub, pas une pré-release.

## Lancement manuel

Dans GitHub :

1. ouvrir **Actions** ;
2. ouvrir **Release signée** ;
3. cliquer **Run workflow** ;
4. saisir un tag, par exemple `v0.6.1` ;
5. choisir si la release doit être marquée comme pré-release.

## Secrets de signature

La liste complète des secrets est documentée dans :

```text
docs/149_releases_signees.md
```

Aucune clé privée, aucun certificat et aucun mot de passe ne doit être versionné dans le dépôt.

## Workflow manuel non signé

Le fichier :

```text
.github/workflows/build_artifacts.yml
```

reste disponible en lancement manuel pour produire des artefacts de test. Il ne se lance plus automatiquement sur les tags afin d’éviter toute confusion avec les releases signées.
