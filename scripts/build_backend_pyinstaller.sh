#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

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
if [[ -z "${BUILD_PYTHON}" ]]; then
  echo "python is required on the build machine (not on teammate machines)." >&2
  echo "Create .venv in the repo root or set PYTHON=/path/to/python." >&2
  exit 1
fi

echo "Using build Python: ${BUILD_PYTHON} ($("${BUILD_PYTHON}" -V 2>&1))"

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

"${BUILD_PYTHON}" -m pip install -r requirements.txt

"${BUILD_PYTHON}" -m PyInstaller "${PYINSTALLER_EXTRA[@]+"${PYINSTALLER_EXTRA[@]}"}" packaging/pyinstaller/backend.spec

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
