#!/usr/bin/env bash
# Strip dev/runtime-unnecessary packages from a bundled inference venv.
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <inference-venv-dir>" >&2
  exit 1
fi

VENV_DIR="$(cd "$1" && pwd)"
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUDGET_FILE="${ROOT_DIR}/inference/tests/bundle_budget.json"

if [[ ! -x "${VENV_DIR}/bin/python" ]]; then
  echo "Not a Python venv: ${VENV_DIR}" >&2
  exit 1
fi

SITE_PACKAGES="$(find "${VENV_DIR}/lib" -type d -name site-packages -print -quit)"
if [[ -z "${SITE_PACKAGES}" ]]; then
  echo "site-packages not found under ${VENV_DIR}" >&2
  exit 1
fi

export SITE_PACKAGES VENV_DIR ROOT_DIR
python3 <<'PY'
import json
import os
import shutil
from pathlib import Path

budget_path = Path(os.environ["ROOT_DIR"]) / "inference/tests/bundle_budget.json"
budget = json.loads(budget_path.read_text())
site_packages = Path(os.environ["SITE_PACKAGES"])
venv_dir = Path(os.environ["VENV_DIR"])

packages = (
    budget.get("forbidden_packages", [])
    + budget.get("target_removals", [])
    + budget.get("optional_removals", [])
)

for name in packages:
    if not name:
        continue
    shutil.rmtree(site_packages / name, ignore_errors=True)
    for dist_info in site_packages.glob(f"{name}-*.dist-info"):
        shutil.rmtree(dist_info, ignore_errors=True)
    for dist_info in site_packages.glob(f"{name.replace('_', '-')}-*.dist-info"):
        shutil.rmtree(dist_info, ignore_errors=True)
    alt = name[:1].upper() + name[1:] if name else name
    for dist_info in site_packages.glob(f"{alt}-*.dist-info"):
        shutil.rmtree(dist_info, ignore_errors=True)
    if name == "markdown_it":
        for dist_info in site_packages.glob("markdown_it_py-*.dist-info"):
            shutil.rmtree(dist_info, ignore_errors=True)

torch_whisper = site_packages / "mlx_whisper" / "torch_whisper.py"
if torch_whisper.exists():
    torch_whisper.unlink()

keep = set(budget.get("transformers_models_keep", []))
models_dir = site_packages / "transformers" / "models"
if keep and models_dir.is_dir():
    for entry in models_dir.iterdir():
        if entry.is_dir() and entry.name not in keep:
            shutil.rmtree(entry, ignore_errors=True)

for extra in ("pip", "setuptools", "pkg_resources"):
    shutil.rmtree(site_packages / extra, ignore_errors=True)
    for dist_info in site_packages.glob(f"{extra}-*.dist-info"):
        shutil.rmtree(dist_info, ignore_errors=True)

for cache_dir in venv_dir.rglob("__pycache__"):
    shutil.rmtree(cache_dir, ignore_errors=True)
for compiled in venv_dir.rglob("*.pyc"):
    compiled.unlink(missing_ok=True)
for compiled in venv_dir.rglob("*.pyo"):
    compiled.unlink(missing_ok=True)
PY

echo "Pruned inference venv at ${VENV_DIR}"
