#!/usr/bin/env bash
set -euo pipefail

if command -v openssl >/dev/null 2>&1; then
  TOKEN="$(openssl rand -hex 32)"
elif command -v python3 >/dev/null 2>&1; then
  TOKEN="$(python3 - <<'PY'
import secrets
print(secrets.token_hex(32))
PY
)"
else
  echo "openssl or python3 is required" >&2
  exit 1
fi

echo "OPENIRN_API_TOKEN=$TOKEN"
echo
echo "À copier dans /etc/openirn-api.env côté serveur, puis dans OpenIRN → Synchronisation."
