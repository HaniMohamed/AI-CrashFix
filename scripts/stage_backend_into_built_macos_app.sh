#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

SRC="${ROOT}/dist/ai_crash_fix_backend/ai_crash_fix_backend"
if [[ ! -f "${SRC}" ]]; then
  echo "Backend binary not found at ${SRC}" >&2
  echo "Run: ./scripts/build_backend_macos.sh" >&2
  exit 1
fi

# Default Flutter build output location. We stage into the newest .app we can find.
PRODUCTS_DIR="${ROOT}/frontend/build/macos/Build/Products"
if [[ ! -d "${PRODUCTS_DIR}" ]]; then
  echo "Flutter macOS build products not found at ${PRODUCTS_DIR}" >&2
  echo "Run: (cd frontend && flutter build macos --debug)" >&2
  exit 1
fi

APP_PATH="${1:-}"
if [[ -z "${APP_PATH}" ]]; then
  # Pick newest built .app under any configuration folder (Debug/Release/Profile).
  APP_PATH="$(
    (
      # With `pipefail`, an empty find -> xargs exit can fail the script.
      set +o pipefail
      /usr/bin/find "${PRODUCTS_DIR}" -maxdepth 3 -name "*.app" -print0 \
        | /usr/bin/xargs -0 ls -td 2>/dev/null \
        | /usr/bin/head -n 1
    ) || true
  )"
fi

if [[ -z "${APP_PATH}" || ! -d "${APP_PATH}" ]]; then
  echo "Could not locate a built .app under ${PRODUCTS_DIR}" >&2
  echo "Pass the app path explicitly: ./scripts/stage_backend_into_built_macos_app.sh /path/to/My.app" >&2
  exit 1
fi

DEST_DIR="${APP_PATH}/Contents/Resources/backend"
DEST="${DEST_DIR}/ai_crash_fix_backend"

mkdir -p "${DEST_DIR}"
cp -f "${SRC}" "${DEST}"
chmod +x "${DEST}"

echo "Staged backend into built app:"
echo "  ${DEST}"

