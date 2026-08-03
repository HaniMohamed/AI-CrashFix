#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

# Optional flags kept for backward compatibility; Step 2 always uses PyInstaller --noconfirm.
VERSION=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --noconfirm|-y)
      shift
      ;;
    --version|-v)
      [[ $# -ge 2 ]] || fail "Missing value for --version"
      VERSION="$2"
      shift 2
      ;;
    -h|--help)
      echo "Usage: $0 <version> [--noconfirm|-y]" >&2
      echo "       $0 --version <version> [--noconfirm|-y]" >&2
      echo "Example: $0 1.2.3" >&2
      echo "         $0 1.2.3+4 --noconfirm" >&2
      exit 0
      ;;
    *)
      if [[ -z "${VERSION}" ]]; then
        VERSION="$1"
        shift
      else
        fail "Unknown option: $1 (usage: $0 <version> [--noconfirm|-y])"
      fi
      ;;
  esac
done

[[ -n "${VERSION}" ]] || fail "version is required (example: $0 1.2.3)"

VERSION_TAG="${VERSION//+/-}"
[[ "${VERSION_TAG}" =~ ^[0-9A-Za-z._-]+$ ]] || fail "invalid version: ${VERSION}"
DMG_PATH="dist/Fixora-${VERSION_TAG}.dmg"

APP_NAME="Fixora.app"
APP_PATH="dist/macos/${APP_NAME}"

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

echo "==> Building Fixora DMG (Flutter macOS + bundled backend)"
echo "Repo: ${ROOT_DIR}"
echo "Using build Python: ${BUILD_PYTHON} ($("${BUILD_PYTHON}" -V 2>&1))"
echo

need_cmd flutter
need_cmd hdiutil

# App icon: prefer Fixora master PNG; fall back to regenerating from favicon.svg.
ICNS="packaging/macos/AppIcon.icns"
ICON_MASTER="packaging/macos/fixora_icon_1024.png"
FAVICON="frontend/web/favicon.svg"
if [[ -f "${ICON_MASTER}" ]]; then
  if [[ ! -f "${ICNS}" ]] || [[ "${ICON_MASTER}" -nt "${ICNS}" ]]; then
    need_cmd iconutil
    need_cmd sips
    echo "==> Generating AppIcon.icns from ${ICON_MASTER}"
    ./scripts/macos_make_icns.sh "${ICON_MASTER}"
    echo
  fi
elif [[ -f "${FAVICON}" ]]; then
  if [[ ! -f "${ICNS}" ]] || [[ "${FAVICON}" -nt "${ICNS}" ]]; then
    need_cmd qlmanage
    need_cmd iconutil
    need_cmd sips
    echo "==> Generating AppIcon.icns from ${FAVICON}"
    ./scripts/macos_icon_from_svg.sh "${FAVICON}"
    echo
  fi
fi

# Sync Flutter AppIcon.appiconset (Dock icon) from Fixora master PNG when present.
ICONSET="frontend/macos/Runner/Assets.xcassets/AppIcon.appiconset"
ICON_SRC=""
if [[ -f "${ICON_MASTER}" ]]; then
  ICON_SRC="${ICON_MASTER}"
elif [[ -f "${FAVICON}" ]]; then
  ICON_SRC="${FAVICON}"
fi
if [[ -n "${ICON_SRC}" ]]; then
  NEED_SYNC=0
  if [[ ! -f "${ICONSET}/app_icon_1024.png" ]] || [[ "${ICON_SRC}" -nt "${ICONSET}/app_icon_1024.png" ]]; then
    NEED_SYNC=1
  fi
  if [[ "${NEED_SYNC}" -eq 1 ]]; then
    need_cmd sips
    echo "==> Syncing Flutter AppIcon.appiconset from ${ICON_SRC}"
    TMP_DIR="dist/.tmp-flutter-icons"
    rm -rf "${TMP_DIR}"
    mkdir -p "${TMP_DIR}" "${ICONSET}"
    PNG="${ICON_SRC}"
    if [[ "${ICON_SRC}" == *.svg ]]; then
      need_cmd qlmanage
      qlmanage -t -s 1024 -o "${TMP_DIR}" "${ICON_SRC}" >/dev/null 2>&1 || fail "Failed to rasterize favicon"
      PNG="$(ls -1 "${TMP_DIR}"/*.png 2>/dev/null | head -n 1 || true)"
      [[ -n "${PNG}" ]] || fail "qlmanage did not produce a PNG"
    fi
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
./scripts/build_macos_app.sh "${VERSION}"
[[ -d "${APP_PATH}" ]] || fail "Missing app bundle at ${APP_PATH}"
echo

echo "==> Step 2: Build backend (PyInstaller)"
# Desktop UI is native Flutter — web assets are optional in the freeze.
# BACKEND_NAME must match app.brand.BACKEND_PROCESS_NAME (Activity Monitor).
BACKEND_NAME="Fixora Backend"
./scripts/build_backend_pyinstaller.sh --noconfirm
[[ -d "dist/${BACKEND_NAME}" ]] || fail "Missing dist/${BACKEND_NAME} (PyInstaller output)"
[[ -x "dist/${BACKEND_NAME}/${BACKEND_NAME}" ]] || fail "Missing backend executable dist/${BACKEND_NAME}/${BACKEND_NAME}"
echo

echo "==> Step 3: Bundle backend + rg into .app"
mkdir -p "${APP_PATH}/Contents/Resources/backend"
mkdir -p "${APP_PATH}/Contents/Resources/bin"

rm -rf "${APP_PATH}/Contents/Resources/backend/${BACKEND_NAME}"
rm -rf "${APP_PATH}/Contents/Resources/backend/ai_crash_fix_backend"
# ditto preserves macOS metadata better than cp -R for large bundles.
ditto "dist/${BACKEND_NAME}" "${APP_PATH}/Contents/Resources/backend/${BACKEND_NAME}"

ditto "${RG_PATH}" "${APP_PATH}/Contents/Resources/bin/rg"
chmod +x "${APP_PATH}/Contents/Resources/bin/rg"
chmod +x "${APP_PATH}/Contents/Resources/backend/${BACKEND_NAME}/${BACKEND_NAME}" || true

BACKEND_BIN="${APP_PATH}/Contents/Resources/backend/${BACKEND_NAME}/${BACKEND_NAME}"
[[ -x "${BACKEND_BIN}" ]] || fail "Backend missing after bundle inject: ${BACKEND_BIN}"

echo "==> Step 3b: Re-sign .app (required after injecting backend)"
# Flutter sealed the app before we added Resources/backend. Without re-signing,
# Gatekeeper treats the install under /Applications as tampered and the embedded
# backend never starts ("API offline").
./scripts/resign_macos_app.sh "${APP_PATH}"
echo

echo "==> Step 4: Build DMG"
./scripts/build_dmg.sh "${VERSION}"
[[ -f "${DMG_PATH}" ]] || fail "Missing ${DMG_PATH}"

# Sanity-check the DMG contains the backend (space-safe mount path).
echo "==> Step 5: Verify DMG contents"
VERIFY_ATTACH="$(hdiutil attach -nobrowse -readonly "${DMG_PATH}")"
VERIFY_MNT="$(echo "${VERIFY_ATTACH}" | sed -n 's/.*\(\/Volumes\/.*\)$/\1/p' | tail -1)"
[[ -n "${VERIFY_MNT}" ]] || fail "Could not mount DMG for verification"
VERIFY_BACKEND="${VERIFY_MNT}/Fixora.app/Contents/Resources/backend/${BACKEND_NAME}/${BACKEND_NAME}"
if [[ ! -x "${VERIFY_BACKEND}" ]]; then
  hdiutil detach "${VERIFY_MNT}" -quiet >/dev/null 2>&1 || true
  fail "DMG is missing embedded backend at Fixora.app/Contents/Resources/backend/..."
fi
hdiutil detach "${VERIFY_MNT}" -quiet >/dev/null 2>&1 || true
echo "DMG backend OK"
echo

echo "Done."
echo "- App: ${APP_PATH}"
echo "- DMG: ${DMG_PATH}"
echo
echo "Install: open the DMG, drag Fixora.app to Applications, then launch from /Applications."
echo "If macOS blocks the first launch: right-click → Open, or:"
echo "  xattr -cr \"/Applications/Fixora.app\""
echo "Closing the app window (or Quit) stops the embedded backend process."
