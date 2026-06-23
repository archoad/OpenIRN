#!/usr/bin/env python3
"""
Prépare le bundle de référentiel à embarquer dans Flutter.

Le script copie le JSON canonique dans `flutter/assets/referentials/` et produit un manifeste.
Il ne modifie pas le contenu fonctionnel du référentiel.

Usage :
  python server/scripts/build_referential_bundle.py \
    --input canonical_irn_v1_1.json \
    --output-dir flutter/assets/referentials
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import shutil
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def load_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def safe_filename(value: str) -> str:
    value = value.lower().replace(".", "_").replace("-", "_")
    value = re.sub(r"[^a-z0-9_]+", "_", value)
    value = re.sub(r"_+", "_", value).strip("_")
    return value or "referential"


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True, help="JSON canonique du référentiel")
    parser.add_argument("--output-dir", required=True, help="Répertoire assets Flutter")
    args = parser.parse_args()

    input_path = Path(args.input)
    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    data = load_json(input_path)
    referential_id = data.get("id") or "adri-irn"
    version = data.get("version") or "unknown"
    filename = f"{safe_filename(referential_id)}.json"
    output_path = output_dir / filename

    shutil.copyfile(input_path, output_path)

    manifest = {
        "generatedAt": datetime.now(timezone.utc).isoformat(),
        "activeReferentialId": referential_id,
        "referentials": [
            {
                "id": referential_id,
                "version": version,
                "filename": filename,
                "assetPath": f"assets/referentials/{filename}",
                "checksumSha256": sha256_file(output_path),
                "pillars": len(data.get("pillars") or []),
                "criteria": len(data.get("criteria") or []),
                "source": data.get("source") or {},
            }
        ],
    }

    manifest_path = output_dir / "manifest.json"
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")

    print(f"Wrote {output_path}")
    print(f"Wrote {manifest_path}")
    print(f"referential={referential_id} version={version} pillars={manifest['referentials'][0]['pillars']} criteria={manifest['referentials'][0]['criteria']}")


if __name__ == "__main__":
    main()
