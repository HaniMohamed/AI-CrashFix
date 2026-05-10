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

# Create a standard "drag to Applications" DMG:
# - DMG root contains: AI Crash Fix.app + Applications (symlink)
STAGE_DIR="${OUT_DIR}/.dmg-stage"
rm -rf "${STAGE_DIR}"
mkdir -p "${STAGE_DIR}"

cp -R "${APP_PATH}" "${STAGE_DIR}/${APP_NAME}"
ln -s "/Applications" "${STAGE_DIR}/Applications"

# Create a read-only DMG from the staging directory.
TMP_DMG="${OUT_DIR}/.tmp-ai-crash-fix.dmg"
rm -f "${TMP_DMG}"

hdiutil create \
  -volname "AI Crash Fix" \
  -srcfolder "${STAGE_DIR}" \
  -ov \
  -format UDZO \
  "${TMP_DMG}"

mv "${TMP_DMG}" "${DMG_PATH}"
rm -rf "${STAGE_DIR}"

echo "DMG created at: ${DMG_PATH}"
