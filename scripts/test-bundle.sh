#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="YouTalkingToMe"
APP_DIR="${ROOT_DIR}/dist/${APP_NAME}.app"
BUDGET_FILE="${ROOT_DIR}/inference/tests/bundle_budget.json"

if [[ ! -d "${APP_DIR}" ]]; then
  echo "Bundle not found at ${APP_DIR}. Run ./scripts/build-app.sh first."
  exit 1
fi

fail() {
  echo "FAIL: $1"
  exit 1
}

pass() {
  echo "PASS: $1"
}

# Structure
[[ -f "${APP_DIR}/Contents/MacOS/${APP_NAME}" ]] || fail "Missing executable"
[[ -f "${APP_DIR}/Contents/Resources/inference/server.py" ]] || fail "Missing inference/server.py"
[[ -f "${APP_DIR}/Contents/Info.plist" ]] || fail "Missing Info.plist"
pass "Bundle structure"

# Size budget
MAX_BYTES="$(python3 -c "import json; print(json.load(open('${BUDGET_FILE}'))['max_bytes'])")"
ACTUAL_BYTES="$(du -sk "${APP_DIR}" | awk '{print $1 * 1024}')"
if (( ACTUAL_BYTES > MAX_BYTES )); then
  fail "Bundle size ${ACTUAL_BYTES} bytes exceeds budget ${MAX_BYTES} bytes"
fi
pass "Bundle size within budget (${ACTUAL_BYTES} bytes)"

# Forbidden packages
FORBIDDEN="$(python3 -c "import json; print(' '.join(json.load(open('${BUDGET_FILE}')).get('forbidden_packages', [])))")"
TARGET_REMOVALS="$(python3 -c "import json; print(' '.join(json.load(open('${BUDGET_FILE}')).get('target_removals', [])))")"
SITE_PACKAGES="${APP_DIR}/Contents/Resources/inference/.venv/lib"
for pkg in ${FORBIDDEN} ${TARGET_REMOVALS}; do
  if find "${SITE_PACKAGES}" -path "*/site-packages/${pkg}" -type d 2>/dev/null | grep -q .; then
    fail "Forbidden package present in bundle: ${pkg}"
  fi
done
pass "Forbidden packages absent"

# No junk in bundled inference
JUNK_COUNT="$(find "${APP_DIR}/Contents/Resources/inference" \( -name '__pycache__' -o -name '*.pyc' \) 2>/dev/null | wc -l | tr -d ' ')"
ENFORCE_JUNK="$(python3 -c "import json; print(json.load(open('${BUDGET_FILE}')).get('enforce_no_cache_junk', False))")"
if [[ "${ENFORCE_JUNK}" == "True" ]] && (( JUNK_COUNT > 0 )); then
  fail "Found ${JUNK_COUNT} __pycache__/.pyc entries in bundle inference"
elif (( JUNK_COUNT > 0 )); then
  echo "WARN: Found ${JUNK_COUNT} cache entries in bundle (set enforce_no_cache_junk=true after cleanup)"
fi
pass "Python cache junk policy"

# Python runnable in bundle
BUNDLE_PYTHON="${APP_DIR}/Contents/Resources/inference/.venv/bin/python"
[[ -x "${BUNDLE_PYTHON}" ]] || fail "Bundled Python not executable"
export PYTHONDONTWRITEBYTECODE=1
"${BUNDLE_PYTHON}" -c "import mlx; import mlx_whisper; import mlx_lm" || fail "Bundled Python imports failed"
pass "Bundled Python imports"

# Server ping from bundle
PING_RESULT="$(
  echo '{"command":"ping"}' | "${BUNDLE_PYTHON}" "${APP_DIR}/Contents/Resources/inference/server.py" 2>/dev/null | head -1
)"
echo "${PING_RESULT}" | grep -q '"ok": true' || fail "Server ping from bundle failed: ${PING_RESULT}"
pass "Server ping from bundle"

# Polish model load (requires cached models — catches broken transformers pruning)
MODELS_CACHE="${HOME}/Library/Application Support/YouTalkingToMe/models"
if [[ -d "${MODELS_CACHE}" ]] && [[ -n "$(ls -A "${MODELS_CACHE}" 2>/dev/null)" ]]; then
  TRANSFORMERS_KEEP="$(python3 -c "import json; keep=json.load(open('${BUDGET_FILE}')).get('transformers_models_keep', []); print('set' if keep else '')")"
  if [[ -n "${TRANSFORMERS_KEEP}" ]]; then
    fail "transformers_models_keep is configured — this breaks AutoTokenizer in the bundle"
  fi
  POLISH_LOAD_RESULT="$(
    "${BUNDLE_PYTHON}" -c "
from pathlib import Path
from huggingface_hub import snapshot_download
from mlx_lm import load

cache = Path.home() / 'Library/Application Support/YouTalkingToMe/models'
path = snapshot_download('mlx-community/gemma-4-e2b-it-4bit', cache_dir=str(cache))
model, tokenizer = load(path)
assert model is not None and tokenizer is not None
print('ok')
" 2>&1
  )" || fail "Bundled polish model load failed: ${POLISH_LOAD_RESULT}"
  pass "Bundled polish model load"
else
  echo "SKIP: Bundled polish model load (models not cached locally)"
fi

# Code signature
codesign -dv "${APP_DIR}" >/dev/null 2>&1 || fail "codesign verification failed"
pass "Code signature valid"

echo "All bundle tests passed."
