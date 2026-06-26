#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

add_plist_bool_key() {
  local file="$1"
  local key="$2"

  if [[ ! -f "$file" ]]; then
    echo "SKIP missing: $file"
    return 0
  fi

  if grep -q "<key>${key}</key>" "$file"; then
    echo "OK ${key}: $file"
    return 0
  fi

  python3 - "$file" "$key" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
key = sys.argv[2]
text = path.read_text()
entry = f"\t<key>{key}</key>\n\t<true/>\n"
idx = text.rfind("</dict>")
if idx == -1:
    raise SystemExit(f"Could not find </dict> in {path}")
path.write_text(text[:idx] + entry + text[idx:])
PY
  echo "ADD ${key}: $file"
}

add_android_permission() {
  local manifest="$ROOT_DIR/flutter/android/app/src/main/AndroidManifest.xml"
  if [[ ! -f "$manifest" ]]; then
    echo "SKIP missing Android manifest: $manifest"
    return 0
  fi

  if grep -q 'android.permission.INTERNET' "$manifest"; then
    echo "OK android.permission.INTERNET: $manifest"
    return 0
  fi

  python3 - "$manifest" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()
permission = '    <uses-permission android:name="android.permission.INTERNET" />\n'
marker = text.find('>')
if marker == -1:
    raise SystemExit(f"Invalid AndroidManifest.xml: {path}")
path.write_text(text[: marker + 1] + "\n" + permission + text[marker + 1:])
PY
  echo "ADD android.permission.INTERNET: $manifest"
}

MACOS_ENTITLEMENTS=(
  "$ROOT_DIR/flutter/macos/Runner/DebugProfile.entitlements"
  "$ROOT_DIR/flutter/macos/Runner/Release.entitlements"
)

for entitlements in "${MACOS_ENTITLEMENTS[@]}"; do
  add_plist_bool_key "$entitlements" "com.apple.security.network.client"
  add_plist_bool_key "$entitlements" "com.apple.security.files.user-selected.read-only"
  add_plist_bool_key "$entitlements" "com.apple.security.files.user-selected.read-write"
done

add_android_permission

echo
echo "Network/file permissions verified. Now run:"
echo "  cd flutter"
echo "  flutter clean"
echo "  flutter pub get"
echo "  flutter run -d macos"
