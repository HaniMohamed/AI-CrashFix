#!/usr/bin/env bash
# Re-sign a macOS .app after injecting unsigned Resources (backend, rg).
# Without this, Gatekeeper rejects the nested backend when the app is installed
# from a DMG into /Applications (Flutter seal no longer matches the bundle).
set -euo pipefail

APP_PATH="${1:-}"
if [[ -z "${APP_PATH}" || ! -d "${APP_PATH}" ]]; then
  echo "Usage: $0 /path/to/Fixora.app" >&2
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENTITLEMENTS="${2:-${ROOT_DIR}/frontend/macos/Runner/Release.entitlements}"

BACKEND_NAME="Fixora Backend"
BACKEND_BIN="${APP_PATH}/Contents/Resources/backend/${BACKEND_NAME}/${BACKEND_NAME}"
# Legacy PyInstaller name (pre-Fixora rebrand)
if [[ ! -x "${BACKEND_BIN}" ]]; then
  BACKEND_BIN="${APP_PATH}/Contents/Resources/backend/ai_crash_fix_backend/ai_crash_fix_backend"
fi
if [[ ! -x "${BACKEND_BIN}" ]]; then
  echo "ERROR: Missing embedded backend at: ${BACKEND_BIN}" >&2
  exit 1
fi

echo "Re-signing app bundle (adhoc, deep)…"
SIGN_ARGS=(--force --deep --sign - --timestamp=none)
if [[ -f "${ENTITLEMENTS}" ]]; then
  SIGN_ARGS+=(--entitlements "${ENTITLEMENTS}")
fi
codesign "${SIGN_ARGS[@]}" "${APP_PATH}"

echo "Verifying signature…"
if ! codesign --verify --deep --strict "${APP_PATH}"; then
  echo "ERROR: codesign --verify failed for ${APP_PATH}" >&2
  echo "  Gatekeeper will block the embedded backend after install to /Applications." >&2
  exit 1
fi

echo "Signature OK: ${APP_PATH}"
