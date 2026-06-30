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

if [[ -d "flutter/assets/referentials" ]]; then
  echo
  echo "[INFO] flutter/assets/referentials existe encore ; validation opportuniste du bundle éventuel."
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

referentials_dir = Path("flutter/assets/referentials")
manifest_path = referentials_dir / "manifest.json"
referential_path = referentials_dir / "adri_irn_v1_1.json"
allowed = {manifest_path, referential_path}

for json_file in sorted(referentials_dir.glob("*.json")):
    if json_file not in allowed:
        fail(f"bundle JSON inattendu : {json_file}")

if manifest_path.exists() or referential_path.exists():
    if not manifest_path.exists() or not referential_path.exists():
        fail("bundle référentiel partiel dans flutter/assets/referentials")
    else:
        try:
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
            referential = json.loads(referential_path.read_text(encoding="utf-8"))
        except Exception as exc:  # noqa: BLE001
            fail(f"bundle référentiel illisible : {exc}")
        else:
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
    ok("aucun bundle référentiel Flutter embarqué à valider")

sys.exit(status)
PY
  if [[ $? -ne 0 ]]; then
    status=1
  fi
fi

echo
if [[ $status -eq 0 ]]; then
  echo "OpenIRN semble prêt pour publication : aucun artefact local évident détecté."
else
  echo "Corrige les erreurs avant publication."
fi

exit "$status"
