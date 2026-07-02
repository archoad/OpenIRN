#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

echo "[OpenIRN 149/150] Vérification de la configuration de release signée Android / Windows"

required_files=(
  ".github/workflows/release.yml"
  "flutter/android/app/build.gradle.kts"
  "docs/149_releases_signees.md"
)

for file in "${required_files[@]}"; do
  if [[ ! -f "$file" ]]; then
    echo "[ERREUR] fichier manquant : $file" >&2
    exit 1
  fi
  echo "[OK] $file"
done

if ! grep -q "ANDROID_KEYSTORE_BASE64" .github/workflows/release.yml; then
  echo "[ERREUR] secrets Android non référencés dans release.yml" >&2
  exit 1
fi
if ! grep -q "WINDOWS_CERTIFICATE_BASE64" .github/workflows/release.yml; then
  echo "[ERREUR] secrets Windows non référencés dans release.yml" >&2
  exit 1
fi
if grep -q "MACOS_CERTIFICATE_BASE64" .github/workflows/release.yml; then
  echo "[AVERTISSEMENT] le workflow release.yml référence encore la signature macOS alors que le profil actif est Android / Windows" >&2
fi
if grep -q "IOS_PROVISIONING_PROFILE_BASE64" .github/workflows/release.yml; then
  echo "[AVERTISSEMENT] le workflow release.yml référence encore la signature iOS alors que le profil actif est Android / Windows" >&2
fi
if ! grep -q "keystoreProperties" flutter/android/app/build.gradle.kts; then
  echo "[ERREUR] signature Android release non configurée dans Gradle" >&2
  exit 1
fi
if ! grep -q "signtool" .github/workflows/release.yml; then
  echo "[ERREUR] signature Windows par signtool absente" >&2
  exit 1
fi

echo "[OK] configuration de release signée Android / Windows présente"
echo "[NOTE] macOS et iOS sont volontairement hors périmètre tant qu'aucun compte Apple Developer payant n'est disponible."
