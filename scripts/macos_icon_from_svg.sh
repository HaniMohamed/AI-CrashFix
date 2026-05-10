#!/usr/bin/env bash
set -euo pipefail

# Generate packaging/macos/AppIcon.icns from an SVG (defaults to frontend/web/favicon.svg)
#
# Uses macOS Quick Look (qlmanage) to rasterize the SVG to 1024px PNG, then
# calls macos_make_icns.sh to produce the .icns.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SVG="${1:-${ROOT_DIR}/frontend/web/favicon.svg}"

if [[ ! -f "${SVG}" ]]; then
  echo "SVG not found: ${SVG}" >&2
  exit 2
fi

command -v qlmanage >/dev/null 2>&1 || { echo "Missing qlmanage (macOS Quick Look)." >&2; exit 2; }

TMP_DIR="${ROOT_DIR}/dist/.tmp-icon"
rm -rf "${TMP_DIR}"
mkdir -p "${TMP_DIR}"

# qlmanage writes output filename itself in the output dir.
qlmanage -t -s 1024 -o "${TMP_DIR}" "${SVG}" >/dev/null 2>&1 || {
  echo "Failed to rasterize SVG via qlmanage." >&2
  exit 2
}

PNG="$(ls -1 "${TMP_DIR}"/*.png 2>/dev/null | head -n 1 || true)"
if [[ -z "${PNG}" ]]; then
  echo "qlmanage did not produce a PNG in ${TMP_DIR}" >&2
  exit 2
fi

"${ROOT_DIR}/scripts/macos_make_icns.sh" "${PNG}"
rm -rf "${TMP_DIR}"

echo "Generated AppIcon.icns from: ${SVG}"

