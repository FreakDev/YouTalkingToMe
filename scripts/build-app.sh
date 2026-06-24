#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="YouTalkingToMe"
BUILD_DIR="${ROOT_DIR}/.build/release"
APP_DIR="${ROOT_DIR}/dist/${APP_NAME}.app"
CONTENTS="${APP_DIR}/Contents"
MACOS="${CONTENTS}/MacOS"
RESOURCES="${CONTENTS}/Resources"

echo "Building Swift release binary..."
cd "${ROOT_DIR}"
swift build -c release

echo "Creating app bundle at ${APP_DIR}"
rm -rf "${APP_DIR}"
mkdir -p "${MACOS}" "${RESOURCES}"

cp "${BUILD_DIR}/${APP_NAME}" "${MACOS}/${APP_NAME}"
cp "${ROOT_DIR}/YouTalkingToMe/Resources/Info.plist" "${CONTENTS}/Info.plist"
cp "${ROOT_DIR}/YouTalkingToMe/Resources/YouTalkingToMe.entitlements" "${CONTENTS}/YouTalkingToMe.entitlements"
if [[ -f "${ROOT_DIR}/YouTalkingToMe/Resources/AppIcon.icns" ]]; then
  cp "${ROOT_DIR}/YouTalkingToMe/Resources/AppIcon.icns" "${RESOURCES}/AppIcon.icns"
else
  echo "Warning: YouTalkingToMe/Resources/AppIcon.icns not found — app will use the default icon."
fi

echo "Copying inference helper..."
mkdir -p "${RESOURCES}/inference"
rsync -a \
  --exclude='/.pytest_cache/' \
  --exclude='/tests/' \
  --exclude='__pycache__/' \
  --exclude='*.pyc' \
  --exclude='*.pyo' \
  --exclude='.venv/lib/python*/site-packages/torch/' \
  --exclude='.venv/lib/python*/site-packages/torchgen/' \
  --exclude='.venv/lib/python*/site-packages/sympy/' \
  --exclude='.venv/lib/python*/site-packages/networkx/' \
  "${ROOT_DIR}/inference/" "${RESOURCES}/inference/"

echo "Pruning bundled Python venv..."
chmod +x "${ROOT_DIR}/scripts/prune-inference-venv.sh"
"${ROOT_DIR}/scripts/prune-inference-venv.sh" "${RESOURCES}/inference/.venv"
find "${RESOURCES}/inference" -type d -name __pycache__ -exec rm -rf {} + 2>/dev/null || true
find "${RESOURCES}/inference" -type f \( -name '*.pyc' -o -name '*.pyo' \) -delete 2>/dev/null || true

chmod +x "${MACOS}/${APP_NAME}"

ENTITLEMENTS="${ROOT_DIR}/YouTalkingToMe/Resources/YouTalkingToMe.entitlements"
echo "Signing app with microphone entitlement..."
codesign --force --deep --sign - --entitlements "${ENTITLEMENTS}" --options runtime "${APP_DIR}"

echo "Verifying entitlements..."
codesign -d --entitlements - "${APP_DIR}" 2>&1 | grep -q "audio-input" || {
  echo "Warning: audio-input entitlement not embedded — microphone permission may not work."
}

echo "Done: ${APP_DIR}"
