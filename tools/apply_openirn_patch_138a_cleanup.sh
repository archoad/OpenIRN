#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

echo "[OpenIRN 138A] Nettoyage des artefacts locaux de publication..."

removed=0
remove_path() {
  local path="$1"
  if [[ -e "$path" ]]; then
    rm -rf "$path"
    echo "  supprimé : $path"
    removed=$((removed + 1))
  fi
}

remove_path ".tmp"
remove_path "docs/.30_publication_github.md.swp"

while IFS= read -r path; do
  rm -f "$path"
  echo "  supprimé : $path"
  removed=$((removed + 1))
done < <(find . \
  \( -name .git -o -path './flutter/build' -o -path './flutter/.dart_tool' -o -path './server/openirn-api/.venv' \) -prune -o \
  -type f \( -name '.DS_Store' -o -name '._*' -o -name '*.swp' -o -name '.*.swp' -o -name '*.swo' -o -name '.*.swo' -o -name '*~' -o -name '*.bak' \) -print)

if [[ $removed -eq 0 ]]; then
  echo "  rien à supprimer"
fi

echo
echo "[OpenIRN 138A] Vérification publication"
./tools/check_open_source_readiness.sh
