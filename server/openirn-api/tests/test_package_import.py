from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path


API_DIR = Path(__file__).resolve().parents[1]


def test_main_can_be_imported_as_uvicorn_package() -> None:
    environment = os.environ.copy()
    environment.pop("PYTHONPATH", None)
    result = subprocess.run(
        [sys.executable, "-c", "import app.main"],
        cwd=API_DIR,
        env=environment,
        capture_output=True,
        text=True,
        check=False,
    )

    assert result.returncode == 0, result.stderr
