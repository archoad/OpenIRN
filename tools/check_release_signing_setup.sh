#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

echo "[OpenIRN] Vérification de la release Android / Windows / Apple et Microsoft Store"

required_files=(
  ".github/workflows/release.yml"
  "flutter/android/app/build.gradle.kts"
  "flutter/pubspec.yaml"
  "flutter/ios/Flutter/Release.xcconfig"
  "flutter/macos/Runner.xcodeproj/project.pbxproj"
  "flutter/macos/Runner/Configs/AppInfo.xcconfig"
  "flutter/windows/runner/resources/msix_logo.png"
  "tools/Test-MsixIconTransparency.ps1"
  "docs/deploiement-applications.md"
  "docs/en/application-deployment.md"
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
  if ! grep -Eq -- "$pattern" .github/workflows/release.yml; then
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
require_pattern 'MSIX_LOGO_PATH:.*msix_logo\.png' 'source transparente de l icône OpenIRN MSIX configurée'
require_pattern '[[:space:]]--logo-path.*MSIX_LOGO_PATH' 'injection de l icône OpenIRN dans le MSIX configurée'
require_pattern 'Square44x44Logo\.targetsize-256\.png' 'contrôle des ressources d icône MSIX configuré'
require_pattern 'qualifiedIconFiles' 'contrôle des ressources MSIX qualifiées par échelle configuré'
require_pattern 'Test-MsixIconTransparency\.ps1' 'contrôle de transparence des icônes MSIX configuré'
require_pattern 'openirn-windows-x64\.msix' 'artefact MSIX de release configuré'
require_pattern 'signtool' 'vérification MSIX par SignTool configurée'
require_pattern 'STORE_MSIX_IDENTITY_NAME:[[:space:]]*archoadFR\.OpenIRN' 'identité MSIX Microsoft Store configurée'
require_pattern 'STORE_MSIX_PUBLISHER:.*0C16A5BC-1E9E-4174-A14C-FD52C54BD219' 'éditeur MSIX Microsoft Store configuré'
require_pattern 'STORE_MSIX_PUBLISHER_DISPLAY_NAME:.*archoad FR' 'nom d éditeur Microsoft Store configuré'
require_pattern 'STORE_MSIX_PFN:[[:space:]]*archoadFR\.OpenIRN_40n6zg9mmw8te' 'PFN Microsoft Store documenté dans le workflow'
require_pattern '[[:space:]]+--store[[:space:]]' 'construction du package de soumission Microsoft Store configurée'
require_pattern 'STORE_MSIX_VERSION=.*storeMsixVersion' 'version MSIX Microsoft Store dédiée configurée'
require_pattern 'name:[[:space:]]*openirn-windows-store-submission' 'artefact de soumission Microsoft Store isolé'
require_pattern 'name:[[:space:]]*Download direct Windows artifacts' 'téléchargement explicite des seuls artefacts Windows directs configuré'
require_pattern 'environment:[[:space:]]*microsoft-store' 'environnement GitHub Microsoft Store configuré'
require_pattern 'microsoft/microsoft-store-apppublisher@v1\.4' 'Microsoft Store Developer CLI v1.4 configuré'
require_pattern 'PARTNER_CENTER_TENANT_ID' 'secret Partner Center Tenant ID référencé'
require_pattern 'PARTNER_CENTER_SELLER_ID' 'secret Partner Center Seller ID référencé'
require_pattern 'PARTNER_CENTER_CLIENT_ID' 'secret Partner Center Client ID référencé'
require_pattern 'PARTNER_CENTER_CLIENT_SECRET' 'secret Partner Center Client Secret référencé'
require_pattern 'MICROSOFT_STORE_PRODUCT_ID:[[:space:]]*9N63P1KPCMMZ' 'identifiant public du produit Microsoft Store configuré'
require_pattern '--inputDirectory' 'répertoire du MSIX Store transmis explicitement au CLI'
if grep -q -- '--inputFile' .github/workflows/release.yml; then
  echo "[ERREUR] option MSStore CLI incompatible --inputFile encore présente" >&2
  exit 1
fi
echo "[OK] option MSStore CLI incompatible --inputFile absente"
require_pattern '--appId.*MICROSOFT_STORE_PRODUCT_ID' 'produit Microsoft Store transmis explicitement au CLI'
require_pattern 'msstore publish' 'soumission automatique Microsoft Store configurée'

if grep -q 'MICROSOFT_STORE_PUBLISH_ENABLED' .github/workflows/release.yml; then
  echo "[ERREUR] la publication Microsoft Store reste conditionnelle" >&2
  exit 1
fi
echo "[OK] soumission Microsoft Store obligatoire pour chaque release"

if grep -Eq 'name:[[:space:]]*Download build artifacts' .github/workflows/release.yml; then
  echo "[ERREUR] téléchargement global des artefacts détecté ; le MSIX Store ne doit pas rejoindre la GitHub Release" >&2
  exit 1
fi
echo "[OK] package Microsoft Store exclu du téléchargement global de release"
require_pattern '^[[:space:]]*lmodern[[:space:]]*\\' 'dépendance LaTeX lmodern configurée pour les PDF'
require_pattern '^[[:space:]]*texlive-fonts-recommended[[:space:]]*\\' 'polices TeX recommandées configurées pour les PDF'
require_pattern 'LICENSE\.txt' 'licence applicative incluse dans les artefacts de release'

require_pattern '^  ios_app_store:' 'job iOS App Store configuré'
require_pattern '^  macos_app_store:' 'job macOS App Store configuré'
require_pattern 'runs-on:[[:space:]]*macos-26' 'runner Apple macOS 26 configuré'
require_pattern 'environment:[[:space:]]*apple-store' 'environnement GitHub Apple Store configuré'
require_pattern 'APP_STORE_CONNECT_KEY_ID' 'variable App Store Connect Key ID référencée'
require_pattern 'APP_STORE_CONNECT_ISSUER_ID' 'variable App Store Connect Issuer ID référencée'
require_pattern 'APPLE_TEAM_ID' 'variable Apple Team ID référencée'
require_pattern 'APP_STORE_CONNECT_PRIVATE_KEY_P8' 'clé privée API App Store Connect référencée'
require_pattern 'IOS_DISTRIBUTION_P12_BASE64' 'certificat de distribution iOS référencé'
require_pattern 'IOS_APP_STORE_PROFILE_BASE64' 'profil iOS App Store référencé'
require_pattern 'MAC_APP_DISTRIBUTION_P12_BASE64' 'certificat Mac App Distribution référencé'
require_pattern 'MAC_INSTALLER_DISTRIBUTION_P12_BASE64' 'certificat Mac Installer Distribution référencé'
require_pattern 'MAC_APP_STORE_PROFILE_BASE64' 'profil Mac App Store référencé'
require_pattern 'flutter build ios' 'configuration Flutter iOS configurée'
require_pattern 'flutter build macos' 'configuration Flutter macOS configurée'
require_pattern 'ios/Flutter/ephemeral/CI-AppStore\.xcconfig' 'configuration de signature iOS limitée à Runner'
require_pattern 'macos/Flutter/ephemeral/CI-AppStore\.xcconfig' 'configuration de signature macOS limitée à Runner'
require_pattern '[[:space:]]-exportArchive' 'export Xcode App Store configuré'
require_pattern '<string>upload</string>' 'téléversement App Store Connect configuré'
require_pattern '[[:space:]]+- ios_app_store' 'publication GitHub dépend de l envoi iOS'
require_pattern '[[:space:]]+- macos_app_store' 'publication GitHub dépend de l envoi macOS'

if grep -Eq '^[[:space:]]+(CODE_SIGN_STYLE|CODE_SIGN_IDENTITY|PROVISIONING_PROFILE_SPECIFIER|OTHER_CODE_SIGN_FLAGS)=' .github/workflows/release.yml; then
  echo "[ERREUR] réglage de signature Xcode global détecté ; il contaminerait les cibles Swift Package" >&2
  exit 1
fi
echo "[OK] aucun réglage de signature Xcode global dans les commandes d archive"

if ! grep -Fq '#include? "ephemeral/CI-AppStore.xcconfig"' flutter/ios/Flutter/Release.xcconfig; then
  echo "[ERREUR] inclusion de signature CI iOS limitée à Runner absente" >&2
  exit 1
fi
if ! grep -Fq '#include? "../../Flutter/ephemeral/CI-AppStore.xcconfig"' flutter/macos/Runner/Configs/AppInfo.xcconfig; then
  echo "[ERREUR] inclusion de signature CI macOS limitée à Runner absente" >&2
  exit 1
fi
if ! grep -Fq 'PROVISIONING_PROFILE_SPECIFIER = "$(OPENIRN_PROVISIONING_PROFILE_SPECIFIER)";' flutter/macos/Runner.xcodeproj/project.pbxproj; then
  echo "[ERREUR] profil de signature CI macOS non limité à la configuration Runner" >&2
  exit 1
fi
echo "[OK] configurations de signature Apple limitées aux cibles Runner"

if grep -Eq 'notarytool|Developer ID Application|Developer ID Installer' .github/workflows/release.yml; then
  echo "[ERREUR] circuit Developer ID hors App Store détecté dans release.yml" >&2
  exit 1
fi

echo "[OK] publication iOS et macOS vers App Store Connect configurée"

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
echo "[OK] configuration de release Android / Windows / Apple et Microsoft Store présente"
