#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

if ! command -v python >/dev/null 2>&1; then
  echo "python is required on the build machine (not on teammate machines)."
  exit 1
fi

PYINSTALLER_EXTRA=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --noconfirm|-y)
      PYINSTALLER_EXTRA+=(--noconfirm)
      shift
      ;;
    *)
      echo "Usage: $0 [--noconfirm|-y]" >&2
      exit 2
      ;;
  esac
done

python -m PyInstaller "${PYINSTALLER_EXTRA[@]+"${PYINSTALLER_EXTRA[@]}"}" packaging/pyinstaller/backend.spec

echo
echo "Built backend bundle at: dist/ai_crash_fix_backend/"
echo "Backend executable:      dist/ai_crash_fix_backend/ai_crash_fix_backend"
