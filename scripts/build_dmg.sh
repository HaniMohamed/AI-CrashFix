#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${ROOT_DIR}/dist"
MACOS_DIR="${OUT_DIR}/macos"
APP_NAME="AI Crash Fix.app"
APP_PATH="${MACOS_DIR}/${APP_NAME}"
DMG_PATH="${OUT_DIR}/AI-Crash-Fix.dmg"

if [[ ! -d "${APP_PATH}" ]]; then
  echo "Missing app bundle at: ${APP_PATH}"
  echo "Run: scripts/build_macos_app.sh"
  exit 1
fi

rm -f "${DMG_PATH}"

# Create a simple read-only DMG containing the .app.
TMP_DMG="${OUT_DIR}/.tmp-ai-crash-fix.dmg"
rm -f "${TMP_DMG}"

hdiutil create \
  -volname "AI Crash Fix" \
  -srcfolder "${APP_PATH}" \
  -ov \
  -format UDZO \
  "${TMP_DMG}"

mv "${TMP_DMG}" "${DMG_PATH}"

echo "DMG created at: ${DMG_PATH}"
