#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

# Optional flags kept for backward compatibility; Step 2 always uses PyInstaller --noconfirm.
while [[ $# -gt 0 ]]; do
  case "$1" in
    --noconfirm|-y)
      shift
      ;;
    *)
      echo "Unknown option: $1" >&2
      echo "Usage: $0 [--noconfirm|-y]" >&2
      exit 2
      ;;
  esac
done

APP_NAME="AI Crash Fix.app"
APP_PATH="dist/macos/${APP_NAME}"

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "Missing required command: $1"
}

resolve_build_python() {
  if [[ -n "${PYTHON:-}" ]]; then
    printf '%s\n' "${PYTHON}"
    return 0
  fi
  if [[ -x "${ROOT_DIR}/.venv/bin/python" ]]; then
    printf '%s\n' "${ROOT_DIR}/.venv/bin/python"
    return 0
  fi
  if command -v python >/dev/null 2>&1; then
    command -v python
    return 0
  fi
  return 1
}

BUILD_PYTHON="$(resolve_build_python || true)"
[[ -n "${BUILD_PYTHON}" ]] || fail "python is required on the build machine. Create .venv or set PYTHON=/path/to/python"

echo "==> Building AI Crash Fix DMG (Flutter macOS + bundled backend)"
echo "Repo: ${ROOT_DIR}"
echo "Using build Python: ${BUILD_PYTHON} ($("${BUILD_PYTHON}" -V 2>&1))"
echo

need_cmd flutter
need_cmd hdiutil

# App icon: regenerate from favicon when missing or favicon is newer.
ICNS="packaging/macos/AppIcon.icns"
FAVICON="frontend/web/favicon.svg"
if [[ -f "${FAVICON}" ]]; then
  if [[ ! -f "${ICNS}" ]] || [[ "${FAVICON}" -nt "${ICNS}" ]]; then
    need_cmd qlmanage
    need_cmd iconutil
    need_cmd sips
    echo "==> Generating AppIcon.icns from ${FAVICON}"
    ./scripts/macos_icon_from_svg.sh "${FAVICON}"
    echo
  fi
fi

# Sync Flutter AppIcon.appiconset from the same favicon (Dock icon).
if [[ -f "${FAVICON}" ]]; then
  ICONSET="frontend/macos/Runner/Assets.xcassets/AppIcon.appiconset"
  NEED_SYNC=0
  if [[ ! -f "${ICONSET}/app_icon_1024.png" ]] || [[ "${FAVICON}" -nt "${ICONSET}/app_icon_1024.png" ]]; then
    NEED_SYNC=1
  fi
  if [[ "${NEED_SYNC}" -eq 1 ]]; then
    need_cmd qlmanage
    need_cmd sips
    echo "==> Syncing Flutter AppIcon.appiconset from ${FAVICON}"
    TMP_DIR="dist/.tmp-flutter-icons"
    rm -rf "${TMP_DIR}"
    mkdir -p "${TMP_DIR}"
    qlmanage -t -s 1024 -o "${TMP_DIR}" "${FAVICON}" >/dev/null 2>&1 || fail "Failed to rasterize favicon"
    PNG="$(ls -1 "${TMP_DIR}"/*.png 2>/dev/null | head -n 1 || true)"
    [[ -n "${PNG}" ]] || fail "qlmanage did not produce a PNG"
    mkdir -p "${ICONSET}"
    sips -z 16 16 "${PNG}" --out "${ICONSET}/app_icon_16.png" >/dev/null
    sips -z 32 32 "${PNG}" --out "${ICONSET}/app_icon_32.png" >/dev/null
    sips -z 64 64 "${PNG}" --out "${ICONSET}/app_icon_64.png" >/dev/null
    sips -z 128 128 "${PNG}" --out "${ICONSET}/app_icon_128.png" >/dev/null
    sips -z 256 256 "${PNG}" --out "${ICONSET}/app_icon_256.png" >/dev/null
    sips -z 512 512 "${PNG}" --out "${ICONSET}/app_icon_512.png" >/dev/null
    sips -z 1024 1024 "${PNG}" --out "${ICONSET}/app_icon_1024.png" >/dev/null
    rm -rf "${TMP_DIR}"
    echo
  fi
fi

# Locate ripgrep to bundle.
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

echo "==> Step 1: Build Flutter macOS (release)"
./scripts/build_macos_app.sh
[[ -d "${APP_PATH}" ]] || fail "Missing app bundle at ${APP_PATH}"
echo

echo "==> Step 2: Build backend (PyInstaller)"
# Desktop UI is native Flutter — web assets are optional in the freeze.
./scripts/build_backend_pyinstaller.sh --noconfirm
[[ -d "dist/ai_crash_fix_backend" ]] || fail "Missing dist/ai_crash_fix_backend (PyInstaller output)"
[[ -x "dist/ai_crash_fix_backend/ai_crash_fix_backend" ]] || fail "Missing backend executable dist/ai_crash_fix_backend/ai_crash_fix_backend"
echo

echo "==> Step 3: Bundle backend + rg into .app"
mkdir -p "${APP_PATH}/Contents/Resources/backend"
mkdir -p "${APP_PATH}/Contents/Resources/bin"

rm -rf "${APP_PATH}/Contents/Resources/backend/ai_crash_fix_backend"
# ditto preserves macOS metadata better than cp -R for large bundles.
ditto "dist/ai_crash_fix_backend" "${APP_PATH}/Contents/Resources/backend/ai_crash_fix_backend"

ditto "${RG_PATH}" "${APP_PATH}/Contents/Resources/bin/rg"
chmod +x "${APP_PATH}/Contents/Resources/bin/rg"
chmod +x "${APP_PATH}/Contents/Resources/backend/ai_crash_fix_backend/ai_crash_fix_backend" || true

BACKEND_BIN="${APP_PATH}/Contents/Resources/backend/ai_crash_fix_backend/ai_crash_fix_backend"
[[ -x "${BACKEND_BIN}" ]] || fail "Backend missing after bundle inject: ${BACKEND_BIN}"

echo "==> Step 3b: Re-sign .app (required after injecting backend)"
# Flutter sealed the app before we added Resources/backend. Without re-signing,
# Gatekeeper treats the install under /Applications as tampered and the embedded
# backend never starts ("API offline").
./scripts/resign_macos_app.sh "${APP_PATH}"
echo

echo "==> Step 4: Build DMG"
./scripts/build_dmg.sh
[[ -f "dist/AI-Crash-Fix.dmg" ]] || fail "Missing dist/AI-Crash-Fix.dmg"

# Sanity-check the DMG contains the backend (space-safe mount path).
echo "==> Step 5: Verify DMG contents"
VERIFY_ATTACH="$(hdiutil attach -nobrowse -readonly "dist/AI-Crash-Fix.dmg")"
VERIFY_MNT="$(echo "${VERIFY_ATTACH}" | sed -n 's/.*\(\/Volumes\/.*\)$/\1/p' | tail -1)"
[[ -n "${VERIFY_MNT}" ]] || fail "Could not mount DMG for verification"
VERIFY_BACKEND="${VERIFY_MNT}/AI Crash Fix.app/Contents/Resources/backend/ai_crash_fix_backend/ai_crash_fix_backend"
if [[ ! -x "${VERIFY_BACKEND}" ]]; then
  hdiutil detach "${VERIFY_MNT}" -quiet >/dev/null 2>&1 || true
  fail "DMG is missing embedded backend at AI Crash Fix.app/Contents/Resources/backend/..."
fi
hdiutil detach "${VERIFY_MNT}" -quiet >/dev/null 2>&1 || true
echo "DMG backend OK"
echo

echo "Done."
echo "- App: ${APP_PATH}"
echo "- DMG: dist/AI-Crash-Fix.dmg"
echo
echo "Install: open the DMG, drag AI Crash Fix.app to Applications, then launch from /Applications."
echo "If macOS blocks the first launch: right-click → Open, or:"
echo "  xattr -cr \"/Applications/AI Crash Fix.app\""
echo "Closing the app window (or Quit) stops the embedded backend process."
