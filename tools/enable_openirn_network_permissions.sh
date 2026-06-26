#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ANDROID_MANIFEST="$ROOT_DIR/flutter/android/app/src/main/AndroidManifest.xml"
MACOS_ENTITLEMENTS=(
  "$ROOT_DIR/flutter/macos/Runner/DebugProfile.entitlements"
  "$ROOT_DIR/flutter/macos/Runner/Release.entitlements"
)

if [[ -f "$ANDROID_MANIFEST" ]]; then
  if ! grep -q 'android.permission.INTERNET' "$ANDROID_MANIFEST"; then
    python3 - "$ANDROID_MANIFEST" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
text = path.read_text()
permission = '    <uses-permission android:name="android.permission.INTERNET" />\n'
if '<manifest' in text and 'android.permission.INTERNET' not in text:
    marker = text.find('>') + 1
    text = text[:marker] + '\n' + permission + text[marker:]
path.write_text(text)
PY
    echo "Added Android INTERNET permission."
  else
    echo "Android INTERNET permission already present."
  fi
else
  echo "Android manifest not found, skipping."
fi

for entitlements in "${MACOS_ENTITLEMENTS[@]}"; do
  if [[ ! -f "$entitlements" ]]; then
    echo "macOS entitlements not found: $entitlements, skipping."
    continue
  fi
  if grep -q 'com.apple.security.network.client' "$entitlements"; then
    echo "macOS network client entitlement already present: $entitlements"
    continue
  fi
  python3 - "$entitlements" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
text = path.read_text()
entry = '\t<key>com.apple.security.network.client</key>\n\t<true/>\n'
idx = text.rfind('</dict>')
if idx == -1:
    raise SystemExit(f'Could not find </dict> in {path}')
text = text[:idx] + entry + text[idx:]
path.write_text(text)
PY
  echo "Added macOS network client entitlement: $entitlements"
done
