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

for forbidden in \
  "Questionnaire_IRN_v.1.1.xlsx" \
  "Questionnaire_IRN_v.1.1.ods" \
  "canonical_irn_v1_1.json" \
  "Evaluation IRN.xlsx" \
  "company_seed.json" \
  "validation_report.json" \
  "validation_referential_report.json"; do
  if [[ -e "$forbidden" ]]; then
    fail "fichier à ne pas publier détecté : $forbidden"
  else
    ok "$forbidden absent"
  fi
done

#if find flutter/assets/referentials -maxdepth 1 -type f -name '*.json' 2>/dev/null | grep -q .; then
#  fail "bundle JSON de référentiel détecté dans flutter/assets/referentials"
#else
#  ok "aucun bundle JSON de référentiel détecté"
#fi

if find . -type f \( -name '*.pem' -o -name '*.key' -o -name '.env' -o -name '.env.*' \) | grep -q .; then
  fail "secret potentiel détecté"
else
  ok "aucun secret évident détecté"
fi

if [[ $status -eq 0 ]]; then
  echo
  echo "OpenIRN semble prêt pour un premier commit public."
else
  echo
  echo "Corrige les erreurs avant publication."
fi

exit "$status"
