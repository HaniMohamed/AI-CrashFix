#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${ROOT_DIR}/dist/macos"
APP_NAME="AI Crash Fix.app"
APP_DIR="${OUT_DIR}/${APP_NAME}"

mkdir -p "${OUT_DIR}"
rm -rf "${APP_DIR}"

mkdir -p "${APP_DIR}/Contents/MacOS"
mkdir -p "${APP_DIR}/Contents/Resources/bin"

# Info.plist
cp "${ROOT_DIR}/packaging/macos/Info.plist" "${APP_DIR}/Contents/Info.plist"

# Optional app icon
if [[ -f "${ROOT_DIR}/packaging/macos/AppIcon.icns" ]]; then
  cp "${ROOT_DIR}/packaging/macos/AppIcon.icns" "${APP_DIR}/Contents/Resources/AppIcon.icns"
fi

# Menu bar template icon (black on transparent PNG for NSImage.isTemplate)
MENUBAR_SVG="${ROOT_DIR}/packaging/macos/menubar_icon.svg"
if [[ -f "${MENUBAR_SVG}" ]] && command -v qlmanage >/dev/null 2>&1; then
  TMP_DIR="${ROOT_DIR}/dist/.tmp-menubar-icon"
  rm -rf "${TMP_DIR}"
  mkdir -p "${TMP_DIR}"
  if qlmanage -t -s 72 -o "${TMP_DIR}" "${MENUBAR_SVG}" >/dev/null 2>&1; then
    PNG="$(ls -1 "${TMP_DIR}"/*.png 2>/dev/null | head -n 1 || true)"
    if [[ -n "${PNG}" ]]; then
      cp "${PNG}" "${APP_DIR}/Contents/Resources/MenuBarIcon.png"
    fi
  fi
  rm -rf "${TMP_DIR}"
fi

# Build the launcher (no Xcode project required)
swiftc \
  -O \
  -framework AppKit \
  "${ROOT_DIR}/packaging/macos/launcher/main.swift" \
  -o "${APP_DIR}/Contents/MacOS/AI_Crash_Fix"

echo "Built launcher at: ${APP_DIR}/Contents/MacOS/AI_Crash_Fix"
echo
echo "Next (after backend/web build steps):"
echo "- copy backend binary to: ${APP_DIR}/Contents/Resources/bin/ai_crash_fix_backend"
echo "- copy ripgrep to:       ${APP_DIR}/Contents/Resources/bin/rg"
echo "- (optional) include icons under Contents/Resources"
