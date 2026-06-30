# GitHub Release workflow

Le workflow de release construit et publie les artefacts OpenIRN lorsqu’un tag `v*` est poussé ou lorsque le workflow est lancé manuellement depuis GitHub Actions.

## Artefacts produits

- `openirn-android.apk`
- `openirn-macos.zip`
- `openirn-windows.zip`
- `openirn-ios-no-codesign.zip`
- `SHA256SUMS.txt`

## Statut de distribution

Ces artefacts sont utiles pour validation et diffusion contrôlée, mais ils ne sont pas encore prêts pour les stores :

- l’APK Android n’est pas configuré pour une signature Play Store ;
- l’application macOS n’est pas signée/notarisée ;
- l’artefact Windows est un ZIP, pas un installateur MSIX ;
- le build iOS est généré avec `--no-codesign`.

## Créer une release

```bash
git tag v0.5.0
git push origin v0.5.0
```

GitHub Actions construit les artefacts et les attache à la release GitHub.

## Lancement manuel

Dans GitHub :

1. ouvrir **Actions** ;
2. ouvrir **Release** ;
3. cliquer **Run workflow** ;
4. saisir un tag, par exemple `v0.5.0` ;
5. choisir si la release est une pré-release.

## Sécurité / publication

Le workflow lance `tools/check_open_source_readiness.sh` avant construction.

Une release ne doit pas embarquer :

- fichiers temporaires ou métadonnées OS ;
- fichiers de travail du référentiel ;
- exports de campagnes privées ;
- données internes d’entreprise ;
- secrets ou certificats.
