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
  "flutter/assets/referentials/manifest.json"
  "flutter/assets/referentials/adri_irn_v1_1.json"
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
    fail "fichier de travail à ne pas publier détecté : $forbidden"
  else
    ok "$forbidden absent"
  fi
done

if [[ -e "flutter/assets/referentials/.gitkeep" ]]; then
  fail "flutter/assets/referentials/.gitkeep doit être supprimé maintenant que le bundle JSON est versionné"
else
  ok "flutter/assets/referentials/.gitkeep absent"
fi

allowed_referential_json=(
  "flutter/assets/referentials/manifest.json"
  "flutter/assets/referentials/adri_irn_v1_1.json"
)

if [[ -d "flutter/assets/referentials" ]]; then
  while IFS= read -r json_file; do
    allowed=false
    for expected in "${allowed_referential_json[@]}"; do
      if [[ "$json_file" == "$expected" ]]; then
        allowed=true
        break
      fi
    done
    if [[ "$allowed" == true ]]; then
      ok "bundle JSON attendu : $json_file"
    else
      fail "bundle JSON inattendu dans flutter/assets/referentials : $json_file"
    fi
  done < <(find flutter/assets/referentials -maxdepth 1 -type f -name '*.json' | sort)
fi

python3 - <<'PY'
import json
from pathlib import Path
import sys

status = 0

def fail(message: str) -> None:
    global status
    print(f"[ERREUR] {message}")
    status = 1

def ok(message: str) -> None:
    print(f"[OK] {message}")

manifest_path = Path("flutter/assets/referentials/manifest.json")
referential_path = Path("flutter/assets/referentials/adri_irn_v1_1.json")

if manifest_path.exists() and referential_path.exists():
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    referential = json.loads(referential_path.read_text(encoding="utf-8"))

    if manifest.get("activeReferentialId") == referential.get("id"):
        ok("manifest cohérent avec le référentiel actif")
    else:
        fail("manifest incohérent avec le référentiel actif")

    if len(referential.get("pillars") or []) == 8:
        ok("référentiel : 8 piliers")
    else:
        fail("référentiel : nombre de piliers inattendu")

    if len(referential.get("criteria") or []) == 30:
        ok("référentiel : 30 critères")
    else:
        fail("référentiel : nombre de critères inattendu")

    source = referential.get("source") or {}
    if source.get("url") and source.get("license"):
        ok("attribution du référentiel présente")
    else:
        fail("attribution du référentiel incomplète")
else:
    fail("impossible de valider le bundle JSON embarqué")

sys.exit(status)
PY
if [[ $? -ne 0 ]]; then
  status=1
fi

if find . -type f \( -name '*.pem' -o -name '*.key' -o -name '.env' -o -name '.env.*' \) | grep -q .; then
  fail "secret potentiel détecté"
else
  ok "aucun secret évident détecté"
fi

if [[ $status -eq 0 ]]; then
  echo
  echo "OpenIRN semble prêt pour publication : le bundle référentiel officiel est embarqué avec attribution."
else
  echo
  echo "Corrige les erreurs avant publication."
fi

exit "$status"
