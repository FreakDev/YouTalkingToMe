#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="YouTalkingToMe"
APP_DIR="${ROOT_DIR}/dist/${APP_NAME}.app"
DERIVED_DATA="${ROOT_DIR}/.derivedData"
XCODE_APP="${DERIVED_DATA}/Build/Products/Release/${APP_NAME}.app"
ENTITLEMENTS="${ROOT_DIR}/YouTalkingToMe/Resources/YouTalkingToMe.entitlements"

if [[ ! -x "${ROOT_DIR}/inference/.venv/bin/python" ]]; then
  echo "Python venv missing. Run ./scripts/bundle-python.sh first."
  exit 1
fi

echo "Building Release app with Xcode (required for MLX metallib bundle)..."
xcodebuild \
  -project "${ROOT_DIR}/YouTalkingToMe.xcodeproj" \
  -scheme "${APP_NAME}" \
  -configuration Release \
  -destination "platform=macOS" \
  -derivedDataPath "${DERIVED_DATA}" \
  -skipMacroValidation \
  build

if [[ ! -d "${XCODE_APP}" ]]; then
  echo "Expected app bundle not found at ${XCODE_APP}"
  exit 1
fi

METALLIB="${XCODE_APP}/Contents/Resources/mlx-swift_Cmlx.bundle/Contents/Resources/default.metallib"
if [[ ! -f "${METALLIB}" ]]; then
  echo "Missing MLX default.metallib — polish inference will crash at launch."
  exit 1
fi

echo "Copying app bundle to ${APP_DIR}"
rm -rf "${APP_DIR}"
cp -R "${XCODE_APP}" "${APP_DIR}"

echo "Pruning bundled Python venv..."
chmod +x "${ROOT_DIR}/scripts/prune-inference-venv.sh"
"${ROOT_DIR}/scripts/prune-inference-venv.sh" "${APP_DIR}/Contents/Resources/inference/.venv"
find "${APP_DIR}/Contents/Resources/inference" -type d -name __pycache__ -exec rm -rf {} + 2>/dev/null || true
find "${APP_DIR}/Contents/Resources/inference" -type f \( -name '*.pyc' -o -name '*.pyo' \) -delete 2>/dev/null || true

echo "Signing app with microphone entitlement..."
codesign --force --deep --sign - --entitlements "${ENTITLEMENTS}" --options runtime "${APP_DIR}"

echo "Verifying entitlements..."
codesign -d --entitlements - "${APP_DIR}" 2>&1 | grep -q "audio-input" || {
  echo "Warning: audio-input entitlement not embedded — microphone permission may not work."
}

echo "Done: ${APP_DIR}"
