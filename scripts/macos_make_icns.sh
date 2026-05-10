#!/usr/bin/env bash
set -euo pipefail

# Create packaging/macos/AppIcon.icns from a 1024x1024 PNG.
#
# Usage:
#   ./scripts/macos_make_icns.sh path/to/icon_1024.png
#
# Requirements (macOS):
# - sips
# - iconutil

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="${1:-}"

if [[ -z "${SRC}" ]]; then
  echo "Usage: $0 path/to/icon_1024.png" >&2
  exit 2
fi
if [[ ! -f "${SRC}" ]]; then
  echo "Icon PNG not found: ${SRC}" >&2
  exit 2
fi

OUT_DIR="${ROOT_DIR}/packaging/macos"
ICONSET="${OUT_DIR}/AppIcon.iconset"
ICNS="${OUT_DIR}/AppIcon.icns"

rm -rf "${ICONSET}"
mkdir -p "${ICONSET}"

mk() {
  local size="$1"
  local name="$2"
  sips -z "${size}" "${size}" "${SRC}" --out "${ICONSET}/${name}" >/dev/null
}

# Standard macOS iconset sizes
mk 16  icon_16x16.png
mk 32  icon_16x16@2x.png
mk 32  icon_32x32.png
mk 64  icon_32x32@2x.png
mk 128 icon_128x128.png
mk 256 icon_128x128@2x.png
mk 256 icon_256x256.png
mk 512 icon_256x256@2x.png
mk 512 icon_512x512.png
mk 1024 icon_512x512@2x.png

iconutil -c icns "${ICONSET}" -o "${ICNS}"
rm -rf "${ICONSET}"

echo "Wrote: ${ICNS}"

