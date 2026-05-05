#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

SRC_DIR="${ROOT}/dist/ai_crash_fix_backend"
SRC_BIN="${SRC_DIR}/ai_crash_fix_backend"
DEST_DIR="${ROOT}/frontend/macos/Runner/Resources/backend/ai_crash_fix_backend"
DEST_BIN="${DEST_DIR}/ai_crash_fix_backend"

if [[ ! -f "${SRC_BIN}" ]]; then
  echo "Backend binary not found at ${SRC_BIN}" >&2
  echo "Run: ./scripts/build_backend_macos.sh" >&2
  exit 1
fi

if [[ ! -d "${ROOT}/frontend/macos" ]]; then
  echo "Flutter macOS target not found at frontend/macos" >&2
  echo "Run (from frontend/): flutter create --platforms=macos ." >&2
  exit 1
fi

rm -rf "${DEST_DIR}"
mkdir -p "$(dirname "${DEST_DIR}")"
cp -R "${SRC_DIR}" "${DEST_DIR}"
chmod +x "${DEST_BIN}"

echo "Staged backend binary to: ${DEST_BIN}"

