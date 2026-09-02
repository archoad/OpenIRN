#!/usr/bin/env bash
set -euo pipefail

# OpenIRN release preflight — Android signé + Windows direct et Microsoft Store.
# Ce script ne lit ni n'affiche les secrets.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

EXPECTED_TAG=""
REQUIRE_SECRETS=false
STRICT=false
WITH_APPLE=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tag)
      EXPECTED_TAG="${2:-}"
      shift 2
      ;;
    --require-secrets)
      REQUIRE_SECRETS=true
      shift
      ;;
    --with-apple)
      WITH_APPLE=true
      shift
      ;;
    --strict)
      STRICT=true
      shift
      ;;
    -h|--help)
      cat <<'USAGE'
Usage: tools/check_openirn_release_preflight.sh [options]

Options:
  --tag vX.Y.Z          Vérifie que le tag correspond à la version Flutter publique.
  --require-secrets    Échoue si les secrets Android/Azure/Partner Center sont absents localement ou dans GitHub.
  --with-apple         Vérifie aussi les prérequis macOS/iOS Apple, optionnels pour l'instant.
  --strict             Transforme certains avertissements en erreurs.
  -h, --help           Affiche cette aide.

Exemples:
  tools/check_openirn_release_preflight.sh
  tools/check_openirn_release_preflight.sh --tag v0.6.1
  tools/check_openirn_release_preflight.sh --tag v0.6.1 --require-secrets
  tools/check_openirn_release_preflight.sh --tag v0.6.1 --with-apple
USAGE
      exit 0
      ;;
    *)
      echo "Option inconnue : $1" >&2
      exit 2
      ;;
  esac
done

ERRORS=0
WARNINGS=0

ok() { printf '[OK] %s\n' "$*"; }
warn() {
  if [[ "$STRICT" == true ]]; then
    printf '[ERREUR] %s\n' "$*" >&2
    ERRORS=$((ERRORS + 1))
  else
    printf '[AVERTISSEMENT] %s\n' "$*" >&2
    WARNINGS=$((WARNINGS + 1))
  fi
}
fail() { printf '[ERREUR] %s\n' "$*" >&2; ERRORS=$((ERRORS + 1)); }

require_file() {
  local path="$1"
  local label="${2:-$1}"
  if [[ -f "$path" ]]; then ok "$label présent"; else fail "$label absent : $path"; fi
}

require_dir() {
  local path="$1"
  local label="${2:-$1}"
  if [[ -d "$path" ]]; then ok "$label présent"; else fail "$label absent : $path"; fi
}

require_grep() {
  local pattern="$1"
  local path="$2"
  local label="$3"
  if [[ -f "$path" ]] && grep -Eq -- "$pattern" "$path"; then ok "$label"; else fail "$label introuvable dans $path"; fi
}

forbidden_grep() {
  local pattern="$1"
  local path="$2"
  local label="$3"
  if [[ -f "$path" ]] && grep -Eq -- "$pattern" "$path"; then fail "$label détecté dans $path"; else ok "$label absent"; fi
}

GITHUB_SECRET_NAMES_CACHE=""
GITHUB_SECRET_NAMES_LOADED=false
GITHUB_SECRET_NAMES_ENVIRONMENT=""

load_github_secret_names() {
  local environment="${1:-}"
  if [[ "$GITHUB_SECRET_NAMES_LOADED" == true && "$GITHUB_SECRET_NAMES_ENVIRONMENT" == "$environment" ]]; then
    return 0
  fi
  GITHUB_SECRET_NAMES_LOADED=true
  GITHUB_SECRET_NAMES_ENVIRONMENT="$environment"
  GITHUB_SECRET_NAMES_CACHE=""

  if ! command -v gh >/dev/null 2>&1; then
    return 0
  fi

  # En local, `gh secret list` permet de vérifier que les secrets existent dans
  # GitHub sans jamais lire leur valeur. En GitHub Actions, les secrets attendus
  # sont normalement injectés comme variables d'environnement par le workflow.
  if [[ -n "$environment" ]]; then
    GITHUB_SECRET_NAMES_CACHE="$(gh secret list --env "$environment" --json name --jq '.[].name' 2>/dev/null || true)"
  else
    GITHUB_SECRET_NAMES_CACHE="$(gh secret list --json name --jq '.[].name' 2>/dev/null || true)"
  fi
}

github_secret_exists() {
  local name="$1"
  local environment="${2:-}"
  load_github_secret_names "$environment"
  [[ -n "$GITHUB_SECRET_NAMES_CACHE" ]] && grep -Fxq "$name" <<<"$GITHUB_SECRET_NAMES_CACHE"
}

check_secret() {
  local name="$1"
  local required="$2"
  local github_environment="${3:-}"
  if [[ -n "${!name:-}" ]]; then
    ok "secret/env ${name} disponible"
  elif github_secret_exists "$name" "$github_environment"; then
    if [[ -n "$github_environment" ]]; then
      ok "secret GitHub ${github_environment} ${name} configuré"
    else
      ok "secret GitHub ${name} configuré"
    fi
  else
    if [[ "$REQUIRE_SECRETS" == true && "$required" == true ]]; then
      fail "secret/env GitHub ${name} manquant"
    else
      warn "secret/env ${name} non présent dans l'environnement courant"
    fi
  fi
}

public_version_from_pubspec() {
  local raw
  raw="$(grep -E '^version:' flutter/pubspec.yaml | head -n1 | awk '{print $2}')"
  printf '%s' "${raw%%+*}"
}

build_number_from_pubspec() {
  local raw
  raw="$(grep -E '^version:' flutter/pubspec.yaml | head -n1 | awk '{print $2}')"
  if [[ "$raw" == *+* ]]; then printf '%s' "${raw#*+}"; else printf ''; fi
}

printf '\n== OpenIRN — préflight release Android / Windows ==\n\n'

printf '== Structure du dépôt ==\n'
require_file README.md README
require_file LICENSE Licence
require_file flutter/assets/legal/GPL-3.0.txt 'licence GPLv3 embarquée'
require_file NOTICE.md Notice
require_file SECURITY.md Sécurité
require_file flutter/pubspec.yaml 'pubspec Flutter'
require_file server/openirn-api/app/main.py 'API serveur'
require_file server/openirn-api/app/version.py 'version API serveur'
require_dir .github/workflows 'workflows GitHub Actions'
require_file .github/workflows/release.yml 'workflow release signé Android / Windows'
require_file .github/workflows/build_artifacts.yml 'workflow artefacts manuel'
require_file tools/check_release_signing_setup.sh 'contrôle de la chaîne de signature'
require_file tools/check_open_source_readiness.sh 'contrôle publication open source'
require_file tools/build_docs.sh 'génération de la documentation PDF'
require_grep 'GPL-3\.0-or-later' README.md 'licence GPL-3.0-or-later déclarée dans le README'
require_grep 'assets/legal/GPL-3\.0\.txt' flutter/pubspec.yaml 'licence GPLv3 embarquée dans l application'
require_grep 'LICENSE\.txt' .github/workflows/release.yml 'licence applicative incluse dans les artefacts de release'

printf '\n== Version et tag ==\n'
PUBLIC_VERSION="$(public_version_from_pubspec)"
BUILD_NUMBER="$(build_number_from_pubspec)"
if [[ -n "$PUBLIC_VERSION" ]]; then ok "version publique Flutter : ${PUBLIC_VERSION}"; else fail "version Flutter illisible dans flutter/pubspec.yaml"; fi
if [[ -n "$BUILD_NUMBER" ]]; then ok "numéro de build Flutter présent : +${BUILD_NUMBER}"; else warn "numéro de build Flutter absent ; recommandé pour les stores mobiles"; fi

if [[ -n "$EXPECTED_TAG" ]]; then
  NORMALIZED_TAG="${EXPECTED_TAG#v}"
  if [[ "$NORMALIZED_TAG" == "$PUBLIC_VERSION" ]]; then ok "tag ${EXPECTED_TAG} cohérent avec la version ${PUBLIC_VERSION}"; else fail "tag ${EXPECTED_TAG} incohérent avec la version publique ${PUBLIC_VERSION}"; fi
else
  warn "aucun tag fourni ; utilisez --tag v${PUBLIC_VERSION} avant publication"
fi

if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  if [[ -n "$(git status --porcelain --untracked-files=no 2>/dev/null || true)" ]]; then warn "des modifications suivies ne sont pas encore commitée(s)"; else ok "aucune modification suivie non commitée"; fi
  if [[ -n "$EXPECTED_TAG" ]]; then
    if git rev-parse -q --verify "refs/tags/${EXPECTED_TAG}" >/dev/null; then
      ok "tag local ${EXPECTED_TAG} présent"
      if git show "${EXPECTED_TAG}:README.md" 2>/dev/null | grep -F 'GPL-3.0-or-later' >/dev/null && \
        git show "${EXPECTED_TAG}:LICENSE" 2>/dev/null | grep -F 'GNU GENERAL PUBLIC LICENSE' >/dev/null; then
        ok "tag local ${EXPECTED_TAG} contient la licence GPL-3.0-or-later"
      else
        fail "tag local ${EXPECTED_TAG} ne contient pas la licence GPL-3.0-or-later"
      fi
      if [[ "$(git rev-list -n 1 "$EXPECTED_TAG")" == "$(git rev-parse HEAD)" ]]; then
        ok "tag local ${EXPECTED_TAG} aligné sur HEAD"
      else
        fail "tag local ${EXPECTED_TAG} attaché à un autre commit que HEAD"
      fi
    else
      warn "tag local ${EXPECTED_TAG} absent ; il sera nécessaire avant git push origin ${EXPECTED_TAG}"
    fi
  fi
else
  warn "dépôt Git non détecté ; contrôle tag/statut ignoré"
fi

printf '\n== Workflow de release ==\n'
require_grep 'name:[[:space:]]*Release sign' .github/workflows/release.yml 'workflow release signé nommé correctement'
require_grep "tags:[[:space:]]*$" .github/workflows/release.yml 'déclenchement par tag présent'
require_grep "'v\*'|\"v\*\"" .github/workflows/release.yml 'tags v* déclenchent la release'
require_grep 'prerelease' .github/workflows/release.yml 'option prerelease présente'
require_grep 'ANDROID_KEYSTORE_BASE64' .github/workflows/release.yml 'signature Android configurée'
require_grep 'azure/artifact-signing-action@v2' .github/workflows/release.yml 'signature Windows Azure Artifact Signing configurée'
require_grep 'id-token:[[:space:]]*write' .github/workflows/release.yml 'permission OIDC GitHub configurée'
require_grep 'environment:[[:space:]]*artifact-signing' .github/workflows/release.yml 'environnement GitHub de signature configuré'
require_grep 'openirnsign' .github/workflows/release.yml 'compte Artifact Signing configuré'
require_grep 'openirn-public' .github/workflows/release.yml 'profil Public Trust configuré'
require_grep 'STORE_MSIX_IDENTITY_NAME:[[:space:]]*archoadFR\.OpenIRN' .github/workflows/release.yml 'identité MSIX Microsoft Store configurée'
require_grep 'STORE_MSIX_PUBLISHER:.*0C16A5BC-1E9E-4174-A14C-FD52C54BD219' .github/workflows/release.yml 'éditeur MSIX Microsoft Store configuré'
require_grep 'STORE_MSIX_PUBLISHER_DISPLAY_NAME:.*archoad FR' .github/workflows/release.yml 'nom d éditeur Microsoft Store configuré'
require_grep '[[:space:]]+--store[[:space:]]' .github/workflows/release.yml 'construction du package de soumission Microsoft Store configurée'
require_grep 'STORE_MSIX_VERSION=.*storeMsixVersion' .github/workflows/release.yml 'version MSIX Microsoft Store dédiée configurée'
require_grep 'name:[[:space:]]*openirn-windows-store-submission' .github/workflows/release.yml 'artefact de soumission Microsoft Store isolé'
require_grep 'name:[[:space:]]*Download direct Windows artifacts' .github/workflows/release.yml 'téléchargement explicite des seuls artefacts Windows directs configuré'
require_grep 'environment:[[:space:]]*microsoft-store' .github/workflows/release.yml 'environnement GitHub Microsoft Store configuré'
require_grep 'microsoft/microsoft-store-apppublisher@v1\.4' .github/workflows/release.yml 'Microsoft Store Developer CLI v1.4 configuré'
require_grep 'PARTNER_CENTER_TENANT_ID' .github/workflows/release.yml 'secret Partner Center Tenant ID référencé'
require_grep 'PARTNER_CENTER_SELLER_ID' .github/workflows/release.yml 'secret Partner Center Seller ID référencé'
require_grep 'PARTNER_CENTER_CLIENT_ID' .github/workflows/release.yml 'secret Partner Center Client ID référencé'
require_grep 'PARTNER_CENTER_CLIENT_SECRET' .github/workflows/release.yml 'secret Partner Center Client Secret référencé'
require_grep 'MICROSOFT_STORE_PRODUCT_ID:[[:space:]]*9N63P1KPCMMZ' .github/workflows/release.yml 'identifiant public du produit Microsoft Store configuré'
require_grep '--inputFile' .github/workflows/release.yml 'MSIX Store transmis explicitement au CLI'
require_grep '--appId.*MICROSOFT_STORE_PRODUCT_ID' .github/workflows/release.yml 'produit Microsoft Store transmis explicitement au CLI'
require_grep 'msstore publish' .github/workflows/release.yml 'soumission automatique Microsoft Store configurée'
forbidden_grep 'MICROSOFT_STORE_PUBLISH_ENABLED' .github/workflows/release.yml 'garde d activation Microsoft Store'
forbidden_grep 'name:[[:space:]]*Download build artifacts' .github/workflows/release.yml 'téléchargement global incluant le package Microsoft Store'
require_grep '^[[:space:]]*lmodern[[:space:]]*\\' .github/workflows/release.yml 'dépendance LaTeX lmodern configurée pour les PDF'
require_grep '^[[:space:]]*texlive-fonts-recommended[[:space:]]*\\' .github/workflows/release.yml 'polices TeX recommandées configurées pour les PDF'
require_grep 'path:[[:space:]]*docs/pdf/openirn-documentation-fr-en\.zip' .github/workflows/release.yml 'archive documentaire bilingue publiée comme artefact unique'
require_grep 'archive_path=.*openirn-documentation-fr-en\.zip' tools/build_docs.sh 'archive documentaire bilingue générée localement'
forbidden_grep 'WINDOWS_CERTIFICATE_BASE64|WINDOWS_CERTIFICATE_PASSWORD|openirn-windows-codesign\.pfx' .github/workflows/release.yml 'ancienne chaîne Windows PFX'
forbidden_grep 'MACOS_CERTIFICATE_BASE64|notarytool|flutter build macos' .github/workflows/release.yml 'release macOS Apple dans le profil courant'
forbidden_grep 'IOS_CERTIFICATE_BASE64|IOS_PROVISIONING_PROFILE_BASE64|flutter build ipa' .github/workflows/release.yml 'release iOS Apple dans le profil courant'
require_grep 'gh release create|gh release upload|softprops/action-gh-release' .github/workflows/release.yml 'publication GitHub Release configurée'
require_grep 'workflow_dispatch' .github/workflows/build_artifacts.yml 'build_artifacts déclenchable manuellement'
if grep -Eq 'push:[[:space:]]*$' .github/workflows/build_artifacts.yml; then warn "build_artifacts.yml semble encore déclenché automatiquement par push"; else ok "build_artifacts.yml ne publie pas automatiquement d'artefacts non signés"; fi

printf '\n== Android ==\n'
require_file flutter/android/app/build.gradle.kts 'Gradle Android Kotlin'
require_grep 'key\.properties' flutter/android/app/build.gradle.kts 'lecture android/key.properties configurée'
require_grep 'signingConfigs' flutter/android/app/build.gradle.kts 'configuration de signature Android présente'
require_file flutter/android/app/src/main/res/drawable/launch_background.xml 'launch_background Android clair'
require_file flutter/android/app/src/main/res/drawable-night/launch_background.xml 'launch_background Android sombre'

printf '\n== Windows ==\n'
require_dir flutter/windows 'projet Windows Flutter'
require_file flutter/windows/runner/resources/msix_logo.png 'icône source OpenIRN transparente pour le MSIX'
require_file tools/Test-MsixIconTransparency.ps1 'contrôle PowerShell de transparence des icônes MSIX'
require_grep 'signtool' .github/workflows/release.yml 'signature Windows par signtool présente'
require_grep 'openirn-windows-signed.zip' .github/workflows/release.yml 'artefact Windows signé configuré'
require_grep 'openirn-windows-x64\.msix' .github/workflows/release.yml 'artefact MSIX signé configuré'
require_grep 'msix:create' .github/workflows/release.yml 'construction MSIX configurée'
require_grep 'MSIX_LOGO_PATH:.*msix_logo\.png' .github/workflows/release.yml 'source transparente de l icône OpenIRN MSIX configurée'
require_grep '[[:space:]]--logo-path.*MSIX_LOGO_PATH' .github/workflows/release.yml 'injection de l icône OpenIRN dans le MSIX configurée'
require_grep 'Square44x44Logo\.targetsize-256\.png' .github/workflows/release.yml 'contrôle des ressources d icône MSIX configuré'
require_grep 'qualifiedIconFiles' .github/workflows/release.yml 'contrôle des ressources MSIX qualifiées par échelle configuré'
require_grep 'Test-MsixIconTransparency\.ps1' .github/workflows/release.yml 'contrôle de transparence des icônes MSIX configuré'
require_grep 'Get-AppxPackage -Name archoadFR\.OpenIRN' docs/deploiement-applications.md 'contrôle du package Microsoft Store documenté en français'
require_grep 'apps\.microsoft\.com/detail/9N63P1KPCMMZ' docs/deploiement-applications.md 'publication Microsoft Store documentée en français'
require_grep 'apps\.microsoft\.com/detail/9N63P1KPCMMZ' docs/en/application-deployment.md 'publication Microsoft Store documentée en anglais'

printf '\n== Apple optionnel ==\n'
if [[ "$WITH_APPLE" == true ]]; then
  require_dir flutter/macos 'projet macOS Flutter'
  require_dir flutter/ios 'projet iOS Flutter'
  check_secret MACOS_CERTIFICATE_BASE64 true
  check_secret MACOS_CERTIFICATE_PASSWORD true
  check_secret MACOS_KEYCHAIN_PASSWORD true
  check_secret APPLE_ID true
  check_secret APPLE_TEAM_ID true
  check_secret APPLE_APP_SPECIFIC_PASSWORD true
  check_secret IOS_CERTIFICATE_BASE64 true
  check_secret IOS_CERTIFICATE_PASSWORD true
  check_secret IOS_PROVISIONING_PROFILE_BASE64 true
else
  ok "macOS/iOS non requis dans le profil actuel Android / Windows"
fi

printf '\n== Secrets de signature attendus ==\n'
for secret in \
  ANDROID_KEYSTORE_BASE64 \
  ANDROID_KEYSTORE_PASSWORD \
  ANDROID_KEY_PASSWORD \
  ANDROID_KEY_ALIAS \
  AZURE_CLIENT_ID \
  AZURE_TENANT_ID \
  AZURE_SUBSCRIPTION_ID; do
  check_secret "$secret" true
done

for secret in \
  PARTNER_CENTER_TENANT_ID \
  PARTNER_CENTER_SELLER_ID \
  PARTNER_CENTER_CLIENT_ID \
  PARTNER_CENTER_CLIENT_SECRET; do
  check_secret "$secret" true microsoft-store
done

printf '\n== Protection des secrets ==\n'
require_file .gitignore '.gitignore'
for pattern in \
  '/secrets/' \
  'flutter/android/key\.properties' \
  '\*\.jks' \
  '\*\.keystore' \
  '\*\.pfx' \
  '\*\.p12' \
  '\*\.mobileprovision'; do
  require_grep "$pattern" .gitignore "protection .gitignore : ${pattern}"
done

if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  TRACKED_SECRETS="$(git ls-files | grep -E '(^|/)(secrets/|key\.properties|.*\.(jks|keystore|pfx|p12|pem|key|p8|mobileprovision))$' || true)"
  if [[ -n "$TRACKED_SECRETS" ]]; then
    printf '%s\n' "$TRACKED_SECRETS" >&2
    fail "des fichiers de signature ou secrets semblent suivis par Git"
  else
    ok "aucun secret de signature détecté dans les fichiers suivis par Git"
  fi
fi

printf '\n== Résultat ==\n'
if [[ "$ERRORS" -gt 0 ]]; then
  printf '[ÉCHEC] %d erreur(s), %d avertissement(s).\n' "$ERRORS" "$WARNINGS" >&2
  exit 1
fi
if [[ "$WARNINGS" -gt 0 ]]; then
  printf '[OK AVEC AVERTISSEMENTS] %d avertissement(s).\n' "$WARNINGS"
else
  printf '[OK] préflight release Android / Windows réussi.\n'
fi
