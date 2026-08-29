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
  "flutter/assets/legal/GPL-3.0.txt"
)

for file in "${required_files[@]}"; do
  if [[ -f "$file" ]]; then
    ok "$file présent"
  else
    fail "$file manquant"
  fi
done

if grep -Fq 'GPL-3.0-or-later' README.md && \
  grep -Fq 'GNU GENERAL PUBLIC LICENSE' LICENSE && \
  grep -Fq 'Version 3, 29 June 2007' LICENSE; then
  ok "licence applicative GPL-3.0-or-later déclarée"
else
  fail "déclaration GPL-3.0-or-later ou texte officiel GPLv3 incomplet"
fi

if cmp -s LICENSE flutter/assets/legal/GPL-3.0.txt; then
  ok "copie GPLv3 embarquée identique au fichier LICENSE"
else
  fail "la copie GPLv3 embarquée diffère du fichier LICENSE"
fi

if grep -Eqi 'Le code OpenIRN est publié sous licence MIT|^MIT License$' README.md LICENSE NOTICE.md CONTRIBUTING.md; then
  fail "ancienne licence MIT encore déclarée comme licence courante"
else
  ok "ancienne licence MIT absente des déclarations courantes"
fi

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

if [[ -d "schemas" ]]; then
  fail "répertoire historique schemas/ encore présent"
else
  ok "répertoire historique schemas/ absent"
fi

if [[ -f "tools/check_release_workflow.sh" ]]; then
  fail "script historique de workflow release encore présent : tools/check_release_workflow.sh"
else
  ok "script historique de workflow release absent"
fi

if [[ -f "tools/enable_openirn_network_permissions.sh" || -f "tools/ensure_openirn_network_permissions.sh" ]]; then
  fail "scripts historiques de permissions réseau encore présents"
  [[ -f "tools/enable_openirn_network_permissions.sh" ]] && echo "  - tools/enable_openirn_network_permissions.sh"
  [[ -f "tools/ensure_openirn_network_permissions.sh" ]] && echo "  - tools/ensure_openirn_network_permissions.sh"
else
  ok "scripts historiques de permissions réseau absents"
fi

if [[ -f "tools/generate_openirn_api_token.sh" ]]; then
  fail "générateur historique du bearer global encore présent : tools/generate_openirn_api_token.sh"
else
  ok "générateur historique du bearer global absent"
fi

if grep -RIn --exclude-dir=.git --exclude='*.png' --exclude='*.jpg' --exclude='*.svg' \
  -E 'bearer de transition|Bearer de transition' docs flutter/lib server/openirn-api/app/main.py >/tmp/openirn_legacy_bearer_labels.txt 2>/dev/null; then
  fail "libellés bearer de transition encore présents"
  sed 's/^/  - /' /tmp/openirn_legacy_bearer_labels.txt
else
  ok "libellés bearer de transition absents"
fi

legacy_db_term="sql""ite"
if grep -RIn --exclude-dir=.git --exclude-dir=build --exclude='*.png' --exclude='*.jpg' --exclude='*.svg' \
  -i "$legacy_db_term" README.md docs flutter/lib server/openirn-api tools >/tmp/openirn_legacy_db_refs.txt 2>/dev/null; then
  fail "références à l’ancien stockage serveur encore présentes"
  sed 's/^/  - /' /tmp/openirn_legacy_db_refs.txt
else
  ok "références à l’ancien stockage serveur absentes"
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

if [[ -x "monitoring/kibana/validate-monitoring.sh" ]]; then
  if monitoring_validation_output=$(monitoring/kibana/validate-monitoring.sh 2>&1); then
    ok "monitoring portable et sans secret évident"
  else
    fail "validation du monitoring en échec"
    echo "${monitoring_validation_output}" | sed 's/^/  - /'
  fi
else
  fail "validateur du monitoring absent ou non exécutable"
fi

echo
if [[ $status -eq 0 ]]; then
  echo "OpenIRN semble prêt pour publication : aucun artefact local évident détecté."
else
  echo "Corrige les erreurs avant publication."
fi

exit "$status"
