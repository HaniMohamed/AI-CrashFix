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

python -m pip install -r requirements.txt

python -m PyInstaller "${PYINSTALLER_EXTRA[@]+"${PYINSTALLER_EXTRA[@]}"}" packaging/pyinstaller/backend.spec

BUNDLE_DIR="dist/ai_crash_fix_backend/_internal"
if [[ ! -d "${BUNDLE_DIR}" ]]; then
  echo "ERROR: Missing PyInstaller bundle at ${BUNDLE_DIR}" >&2
  exit 1
fi
if ! find "${BUNDLE_DIR}" -maxdepth 3 \( -path '*/psycopg/*' -o -path '*/psycopg_binary/*' \) | grep -q .; then
  echo "ERROR: psycopg/psycopg_binary not found in PyInstaller bundle" >&2
  exit 1
fi
if ! find "${BUNDLE_DIR}/psycopg_binary" -name '*.so' -print -quit | grep -q .; then
  echo "ERROR: psycopg_binary native extension not found in PyInstaller bundle" >&2
  exit 1
fi

echo
echo "Built backend bundle at: dist/ai_crash_fix_backend/"
echo "Backend executable:      dist/ai_crash_fix_backend/ai_crash_fix_backend"
