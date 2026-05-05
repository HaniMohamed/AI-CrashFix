#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

SRC="${ROOT}/dist/ai_crash_fix_backend/ai_crash_fix_backend"
DEST_DIR="${ROOT}/frontend/macos/Runner/Resources/backend"
DEST="${DEST_DIR}/ai_crash_fix_backend"

if [[ ! -f "${SRC}" ]]; then
  echo "Backend binary not found at ${SRC}" >&2
  echo "Run: ./scripts/build_backend_macos.sh" >&2
  exit 1
fi

if [[ ! -d "${ROOT}/frontend/macos" ]]; then
  echo "Flutter macOS target not found at frontend/macos" >&2
  echo "Run (from frontend/): flutter create --platforms=macos ." >&2
  exit 1
fi

mkdir -p "${DEST_DIR}"
cp -f "${SRC}" "${DEST}"
chmod +x "${DEST}"

echo "Staged backend binary to: ${DEST}"

