#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
RUN_SMOKE=false
RUN_BUNDLE=false

for arg in "$@"; do
  case "${arg}" in
    --smoke) RUN_SMOKE=true ;;
    --bundle) RUN_BUNDLE=true ;;
    --all)
      RUN_SMOKE=true
      RUN_BUNDLE=true
      ;;
    *)
      echo "Usage: $0 [--smoke] [--bundle] [--all]"
      exit 1
      ;;
  esac
done

echo "==> Python unit tests"
VENV_PYTHON="${ROOT_DIR}/inference/.venv/bin/python"
if [[ ! -x "${VENV_PYTHON}" ]]; then
  echo "Python venv missing. Run ./scripts/bundle-python.sh first."
  exit 1
fi

if ! "${VENV_PYTHON}" -c "import pytest" 2>/dev/null; then
  echo "Installing dev test dependencies..."
  "${VENV_PYTHON}" -m pip install -r "${ROOT_DIR}/inference/requirements-dev.txt"
fi

PYTEST_ARGS=()
if [[ "${RUN_SMOKE}" == true ]]; then
  PYTEST_ARGS+=(--smoke)
fi

(cd "${ROOT_DIR}/inference" && "${VENV_PYTHON}" -m pytest tests/ ${PYTEST_ARGS[@]+"${PYTEST_ARGS[@]}"})

echo "==> Swift unit tests"
if [[ -d "/Applications/Xcode.app/Contents/Developer" ]]; then
  DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer" swift test --package-path "${ROOT_DIR}"
elif xcrun --find swift 2>/dev/null | grep -q "Xcode.app"; then
  (cd "${ROOT_DIR}" && swift test)
else
  echo "Skipping Swift tests: XCTest requires Xcode.app (Command Line Tools alone are not enough)."
fi

if [[ "${RUN_BUNDLE}" == true ]]; then
  echo "==> Bundle tests"
  chmod +x "${ROOT_DIR}/scripts/test-bundle.sh"
  "${ROOT_DIR}/scripts/test-bundle.sh"
fi

echo "All tests passed."
