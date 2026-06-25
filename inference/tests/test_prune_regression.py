"""Regression tests for bundle pruning — must not break polish tokenizer loading."""

from __future__ import annotations

import json
import subprocess
from pathlib import Path

import pytest

from conftest import models_cached

BUDGET_FILE = Path(__file__).resolve().parent / "bundle_budget.json"
POLISH_REPO = "mlx-community/gemma-4-e2b-it-4bit"


def _budget() -> dict:
    return json.loads(BUDGET_FILE.read_text())


def _venv_python() -> Path:
    return Path(__file__).resolve().parents[1] / ".venv" / "bin" / "python"


def _load_polish_model_with_python(python: Path, site_packages: Path) -> subprocess.CompletedProcess[str]:
    import os

    script = f"""
from pathlib import Path
from huggingface_hub import snapshot_download
from mlx_lm import load

cache = Path.home() / "Library/Application Support/YouTalkingToMe/models"
path = snapshot_download({POLISH_REPO!r}, cache_dir=str(cache))
load(path)
print("ok")
"""
    env = os.environ.copy()
    env["PYTHONPATH"] = str(site_packages)
    return subprocess.run(
        [str(python), "-I", "-c", script],
        capture_output=True,
        text=True,
        timeout=120,
        env=env,
    )


def test_budget_disallows_transformers_model_pruning():
    keep = _budget().get("transformers_models_keep") or []
    assert not keep, (
        "transformers_models_keep must stay empty: AutoTokenizer scans all "
        "transformers.models modules and pruning breaks polish model loading."
    )


@pytest.mark.skipif(not models_cached(), reason="ML models not cached locally")
def test_polish_model_loads_in_dev_venv():
    python = _venv_python()
    if not python.exists():
        pytest.skip("dev venv missing")
    site_packages = next((python.parent.parent / "lib").glob("python*/site-packages"))
    result = _load_polish_model_with_python(python, site_packages)
    assert result.returncode == 0, result.stderr or result.stdout
