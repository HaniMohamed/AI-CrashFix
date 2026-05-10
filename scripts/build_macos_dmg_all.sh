#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

APP_NAME="AI Crash Fix.app"
APP_PATH="dist/macos/${APP_NAME}"

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "Missing required command: $1"
}

echo "==> Building AI Crash Fix DMG (all steps)"
echo "Repo: ${ROOT_DIR}"
echo

# Build-time prerequisites (teammates don't need these; only the release builder does).
need_cmd python
need_cmd flutter
need_cmd swiftc
need_cmd hdiutil

# Generate the app icon (use the existing favicon.svg by default).
#
# If you want a different icon, pre-create packaging/macos/AppIcon.icns before running
# this script and it will be used as-is.
if [[ -f "frontend/web/favicon.svg" ]] && [[ ! -f "packaging/macos/AppIcon.icns" ]]; then
  need_cmd qlmanage
  need_cmd iconutil
  need_cmd sips
  echo "==> Generating AppIcon.icns from frontend/web/favicon.svg"
  ./scripts/macos_icon_from_svg.sh "frontend/web/favicon.svg"
  echo
fi

# Locate ripgrep to bundle.
# Priority:
# - RG_PATH env var
# - common Homebrew / system locations
RG_PATH="${RG_PATH:-}"
if [[ -z "${RG_PATH}" ]]; then
  for p in /opt/homebrew/bin/rg /usr/local/bin/rg /usr/bin/rg; do
    if [[ -x "${p}" ]]; then
      RG_PATH="${p}"
      break
    fi
  done
fi
[[ -n "${RG_PATH}" ]] || fail "ripgrep not found. Install it on the build machine or set RG_PATH=/path/to/rg"
[[ -x "${RG_PATH}" ]] || fail "RG_PATH is not executable: ${RG_PATH}"

echo "Using rg from: ${RG_PATH}"
echo

echo "==> Step 1: Build Flutter Web"
pushd frontend >/dev/null
flutter pub get
flutter build web --release
popd >/dev/null
[[ -f "frontend/build/web/index.html" ]] || fail "Flutter build did not produce frontend/build/web/index.html"
echo

echo "==> Step 2: Build backend (PyInstaller)"
./scripts/build_backend_pyinstaller.sh
[[ -d "dist/ai_crash_fix_backend" ]] || fail "Missing dist/ai_crash_fix_backend (PyInstaller output)"
[[ -x "dist/ai_crash_fix_backend/ai_crash_fix_backend" ]] || fail "Missing backend executable dist/ai_crash_fix_backend/ai_crash_fix_backend"
echo

echo "==> Step 3: Build macOS .app (launcher)"
./scripts/build_macos_app.sh
[[ -d "${APP_PATH}" ]] || fail "Missing app bundle at ${APP_PATH}"
echo

echo "==> Step 4: Bundle backend + rg into .app"
mkdir -p "${APP_PATH}/Contents/Resources/bin"

# Backend (onedir bundle)
rm -rf "${APP_PATH}/Contents/Resources/bin/ai_crash_fix_backend"
cp -R "dist/ai_crash_fix_backend" "${APP_PATH}/Contents/Resources/bin/ai_crash_fix_backend"

# ripgrep
cp "${RG_PATH}" "${APP_PATH}/Contents/Resources/bin/rg"
chmod +x "${APP_PATH}/Contents/Resources/bin/"*
echo

echo "==> Step 5: Build DMG"
./scripts/build_dmg.sh
[[ -f "dist/AI-Crash-Fix.dmg" ]] || fail "Missing dist/AI-Crash-Fix.dmg"
echo

echo "Done."
echo "- App: ${APP_PATH}"
echo "- DMG: dist/AI-Crash-Fix.dmg"

