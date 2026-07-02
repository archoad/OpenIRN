#!/usr/bin/env bash
set -euo pipefail

# OpenIRN release preflight — profil courant : Android signé + Windows signé.
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
  --require-secrets    Échoue si les variables d'environnement Android/Windows sont absentes.
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
  if [[ -f "$path" ]] && grep -Eq "$pattern" "$path"; then ok "$label"; else fail "$label introuvable dans $path"; fi
}

forbidden_grep() {
  local pattern="$1"
  local path="$2"
  local label="$3"
  if [[ -f "$path" ]] && grep -Eq "$pattern" "$path"; then fail "$label détecté dans $path"; else ok "$label absent"; fi
}

check_secret() {
  local name="$1"
  local required="$2"
  if [[ -n "${!name:-}" ]]; then
    ok "secret/env ${name} disponible"
  else
    if [[ "$REQUIRE_SECRETS" == true && "$required" == true ]]; then
      fail "secret/env ${name} manquant"
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
require_file NOTICE.md Notice
require_file SECURITY.md Sécurité
require_file flutter/pubspec.yaml 'pubspec Flutter'
require_file server/openirn-api/app/main.py 'API serveur'
require_dir .github/workflows 'workflows GitHub Actions'
require_file .github/workflows/release.yml 'workflow release signé Android / Windows'
require_file .github/workflows/build_artifacts.yml 'workflow artefacts manuel'
require_file tools/check_release_signing_setup.sh 'contrôle signature 149/150'
require_file tools/check_open_source_readiness.sh 'contrôle publication open source'

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
    if git rev-parse -q --verify "refs/tags/${EXPECTED_TAG}" >/dev/null; then ok "tag local ${EXPECTED_TAG} présent"; else warn "tag local ${EXPECTED_TAG} absent ; il sera nécessaire avant git push origin ${EXPECTED_TAG}"; fi
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
require_grep 'WINDOWS_CERTIFICATE_BASE64' .github/workflows/release.yml 'signature Windows configurée'
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
require_grep 'signtool' .github/workflows/release.yml 'signature Windows par signtool présente'
require_grep 'openirn-windows-signed.zip' .github/workflows/release.yml 'artefact Windows signé configuré'

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
  WINDOWS_CERTIFICATE_BASE64 \
  WINDOWS_CERTIFICATE_PASSWORD; do
  check_secret "$secret" true
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
