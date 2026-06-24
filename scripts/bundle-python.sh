#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VENV_DIR="${ROOT_DIR}/inference/.venv"
REQUIREMENTS="${ROOT_DIR}/inference/requirements.txt"

if [[ ! -d "${VENV_DIR}" ]]; then
  python3 -m venv "${VENV_DIR}"
fi

"${VENV_DIR}/bin/pip" install --upgrade pip
"${VENV_DIR}/bin/pip" install -r "${REQUIREMENTS}"

# mlx-whisper declares torch but the MLX code path never imports it.
"${VENV_DIR}/bin/pip" uninstall -y torch sympy networkx 2>/dev/null || true

echo "Python inference environment ready at ${VENV_DIR}"
