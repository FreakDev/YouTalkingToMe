#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
RESOURCES="${ROOT_DIR}/YouTalkingToMe/Resources"
SOURCE_PNG="${RESOURCES}/icon-1024.png"
ICONSET="${RESOURCES}/AppIcon.iconset"
OUTPUT="${RESOURCES}/AppIcon.icns"

if [[ ! -f "${SOURCE_PNG}" ]]; then
  echo "Missing source icon: ${SOURCE_PNG}"
  echo "Place a 1024x1024 PNG at that path and rerun."
  exit 1
fi

rm -rf "${ICONSET}"
mkdir -p "${ICONSET}"

# Strip quarantine/metadata that can make iconutil reject the iconset.
xattr -cr "${SOURCE_PNG}"

sips -z 16 16     "${SOURCE_PNG}" --out "${ICONSET}/icon_16x16.png"
sips -z 32 32     "${SOURCE_PNG}" --out "${ICONSET}/icon_16x16@2x.png"
sips -z 32 32     "${SOURCE_PNG}" --out "${ICONSET}/icon_32x32.png"
sips -z 64 64     "${SOURCE_PNG}" --out "${ICONSET}/icon_32x32@2x.png"
sips -z 128 128   "${SOURCE_PNG}" --out "${ICONSET}/icon_128x128.png"
sips -z 256 256   "${SOURCE_PNG}" --out "${ICONSET}/icon_128x128@2x.png"
sips -z 256 256   "${SOURCE_PNG}" --out "${ICONSET}/icon_256x256.png"
sips -z 512 512   "${SOURCE_PNG}" --out "${ICONSET}/icon_256x256@2x.png"
sips -z 512 512   "${SOURCE_PNG}" --out "${ICONSET}/icon_512x512.png"
sips -z 1024 1024 "${SOURCE_PNG}" --out "${ICONSET}/icon_512x512@2x.png"

xattr -cr "${ICONSET}"
iconutil -c icns "${ICONSET}" -o "${OUTPUT}"

echo "Generated ${OUTPUT}"
