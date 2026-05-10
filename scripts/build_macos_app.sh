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
