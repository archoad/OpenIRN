#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

echo "[OpenIRN] Vérification de la configuration de release signée Android / Windows Artifact Signing"

required_files=(
  ".github/workflows/release.yml"
  "flutter/android/app/build.gradle.kts"
  "flutter/pubspec.yaml"
  "flutter/ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png"
  "docs/deploiement-applications.md"
)

for file in "${required_files[@]}"; do
  if [[ ! -f "$file" ]]; then
    echo "[ERREUR] fichier manquant : $file" >&2
    exit 1
  fi
  echo "[OK] $file"
done

require_pattern() {
  local pattern="$1"
  local label="$2"
  if ! grep -Eq "$pattern" .github/workflows/release.yml; then
    echo "[ERREUR] ${label}" >&2
    exit 1
  fi
  echo "[OK] ${label}"
}

if ! grep -q "ANDROID_KEYSTORE_BASE64" .github/workflows/release.yml; then
  echo "[ERREUR] secrets Android non référencés dans release.yml" >&2
  exit 1
fi

echo "[OK] signature Android configurée"

require_pattern 'id-token:[[:space:]]*write' 'permission OIDC id-token: write présente'
require_pattern 'environment:[[:space:]]*artifact-signing' 'environnement GitHub artifact-signing configuré'
require_pattern 'azure/login@v3' 'authentification Azure OIDC configurée'
require_pattern 'AZURE_CLIENT_ID' 'secret AZURE_CLIENT_ID référencé'
require_pattern 'AZURE_TENANT_ID' 'secret AZURE_TENANT_ID référencé'
require_pattern 'AZURE_SUBSCRIPTION_ID' 'secret AZURE_SUBSCRIPTION_ID référencé'
require_pattern 'azure/artifact-signing-action@v2' 'Azure Artifact Signing v2 configuré'
require_pattern 'openirnsign' 'compte Artifact Signing openirnsign configuré'
require_pattern 'openirn-public' 'profil Artifact Signing openirn-public configuré'
require_pattern 'msix:create' 'construction MSIX configurée'
require_pattern 'MSIX_LOGO_PATH:.*Icon-App-1024x1024@1x\.png' 'source de l icône OpenIRN MSIX configurée'
require_pattern '[[:space:]]--logo-path.*MSIX_LOGO_PATH' 'injection de l icône OpenIRN dans le MSIX configurée'
require_pattern 'Square44x44Logo\.targetsize-256\.png' 'contrôle des ressources d icône MSIX configuré'
require_pattern 'openirn-windows-x64\.msix' 'artefact MSIX de release configuré'
require_pattern 'signtool' 'vérification MSIX par SignTool configurée'
require_pattern '^[[:space:]]*lmodern[[:space:]]*\\' 'dépendance LaTeX lmodern configurée pour les PDF'
require_pattern 'LICENSE\.txt' 'licence applicative incluse dans les artefacts de release'

if grep -Eq 'WINDOWS_CERTIFICATE_BASE64|WINDOWS_CERTIFICATE_PASSWORD|openirn-windows-codesign\.pfx' .github/workflows/release.yml; then
  echo "[ERREUR] ancienne chaîne Windows PFX encore référencée dans release.yml" >&2
  exit 1
fi

echo "[OK] aucune dépendance à un PFX Windows exporté"

if ! grep -q "keystoreProperties" flutter/android/app/build.gradle.kts; then
  echo "[ERREUR] signature Android release non configurée dans Gradle" >&2
  exit 1
fi

if ! grep -Eq '^[[:space:]]*msix:[[:space:]]*\^?[0-9]' flutter/pubspec.yaml; then
  echo "[ERREUR] dépendance Dart msix absente de flutter/pubspec.yaml" >&2
  exit 1
fi

echo "[OK] dépendance MSIX présente"
echo "[OK] configuration de release signée Android / Windows Artifact Signing présente"
echo "[NOTE] macOS et iOS restent volontairement hors périmètre du profil courant."
