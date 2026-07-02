#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

status=0

fail() {
  echo "[ERREUR] $1"
  status=1
}

ok() {
  echo "[OK] $1"
}

required_files=(
  "README.md"
  "LICENSE"
  "NOTICE.md"
  "CONTRIBUTING.md"
  "SECURITY.md"
  "CODE_OF_CONDUCT.md"
  ".gitignore"
)

for file in "${required_files[@]}"; do
  if [[ -f "$file" ]]; then
    ok "$file présent"
  else
    fail "$file manquant"
  fi
done

check_absent_find() {
  local description="$1"
  shift
  local matches
  matches=$(find . \
    \( -name .git -o -path './flutter/build' -o -path './flutter/.dart_tool' -o -path './server/openirn-api/.venv' -o -path './node_modules' \) -prune -o \
    "$@" -print | sort)
  if [[ -n "$matches" ]]; then
    fail "$description détecté :"
    echo "$matches" | sed 's/^/  - /'
  else
    ok "$description absent"
  fi
}

check_absent_find "métadonnées macOS" -type f \( -name '.DS_Store' -o -name '._*' \)
check_absent_find "swap ou sauvegarde d’éditeur" -type f \( -name '*.swp' -o -name '.*.swp' -o -name '*.swo' -o -name '.*.swo' -o -name '*~' -o -name '*.bak' \)

if [[ -d ".tmp" ]]; then
  fail "répertoire temporaire .tmp présent"
else
  ok "répertoire temporaire .tmp absent"
fi

check_absent_find "fichier de travail référentiel" -type f \( \
  -name 'Questionnaire_IRN_*.xlsx' -o \
  -name 'Questionnaire_IRN_*.ods' -o \
  -name 'canonical_irn_*.json' -o \
  -name 'validation_referential_report.json' \
\)

check_absent_find "donnée entreprise ou campagne exportée" -type f \( \
  -name 'Evaluation IRN*.xlsx' -o \
  -name 'company_seed.json' -o \
  -name 'validation_report.json' -o \
  -name 'openirn_*.json' -o \
  -name '*_campaign_export.json' \
\)

check_absent_find "secret potentiel" -type f \( \
  -name '.env' -o \
  -name '.env.*' -o \
  -name '*.pem' -o \
  -name '*.key' -o \
  -name '*.p12' -o \
  -name '*.mobileprovision' \
\)

# Since patch 123B / 138C, the Flutter application must not embed the
# official referential. The active referential is installed, served and
# historized by the API. Keep import and validation scripts, but reject the
# old runtime bundle and its generator.
if [[ -d "flutter/assets/referentials" ]]; then
  fail "ancien bundle référentiel Flutter embarqué présent : flutter/assets/referentials"
else
  ok "ancien bundle référentiel Flutter embarqué absent"
fi

if [[ -f "flutter/pubspec_fragment.yaml" ]]; then
  fail "fragment pubspec historique encore présent : flutter/pubspec_fragment.yaml"
else
  ok "fragment pubspec historique absent"
fi

if [[ -f "server/scripts/build_referential_bundle.py" ]]; then
  fail "générateur historique de bundle Flutter encore présent : server/scripts/build_referential_bundle.py"
else
  ok "générateur historique de bundle Flutter absent"
fi

if [[ -f "flutter/pubspec.yaml" ]] && grep -Fq "assets/referentials" "flutter/pubspec.yaml"; then
  fail "pubspec.yaml déclare encore assets/referentials"
else
  ok "pubspec.yaml ne déclare pas assets/referentials"
fi

echo
if [[ $status -eq 0 ]]; then
  echo "OpenIRN semble prêt pour publication : aucun artefact local évident détecté."
else
  echo "Corrige les erreurs avant publication."
fi

exit "$status"
