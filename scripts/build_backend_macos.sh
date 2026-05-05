#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

PY="${ROOT}/.venv/bin/python"

if [[ ! -x "${PY}" ]]; then
  echo "Missing venv python at ${PY}" >&2
  exit 1
fi

echo "Building backend with PyInstaller..."
cd "${ROOT}"

"${PY}" -m PyInstaller --noconfirm --clean packaging/pyinstaller/backend.spec

echo "Built dist/ai_crash_fix_backend/ai_crash_fix_backend"

if [[ "${1:-}" == "--stage-into-built-app" ]]; then
  echo "Staging backend into the newest built .app..."
  "${ROOT}/scripts/stage_backend_into_built_macos_app.sh"
fi

