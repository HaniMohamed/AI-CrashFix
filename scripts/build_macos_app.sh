#!/usr/bin/env bash
set -euo pipefail

# Build the Flutter macOS release app and stage it at dist/macos/Fixora.app
# (backend + rg are injected by build_macos_dmg_all.sh / callers).

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${ROOT_DIR}/dist/macos"
APP_NAME="Fixora.app"
APP_DIR="${OUT_DIR}/${APP_NAME}"

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required command: $1" >&2
    exit 2
  }
}

need_cmd flutter

VERSION=""
if [[ $# -gt 0 && "$1" != --* ]]; then
  VERSION="$1"
  shift
fi
while [[ $# -gt 0 ]]; do
  case "$1" in
    --version|-v)
      [[ $# -ge 2 ]] || {
        echo "Usage: $0 [<version>] [--version <version>]" >&2
        exit 2
      }
      VERSION="$2"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

flutter_build_args=(build macos --release)
if [[ -n "${VERSION}" ]]; then
  BUILD_NAME="${VERSION%%+*}"
  if [[ "${VERSION}" == *+* ]]; then
    BUILD_NUMBER="${VERSION#*+}"
  else
    BUILD_NUMBER=""
  fi
  flutter_build_args+=(--build-name="${BUILD_NAME}")
  if [[ -n "${BUILD_NUMBER}" ]]; then
    flutter_build_args+=(--build-number="${BUILD_NUMBER}")
  fi
  echo "==> flutter build macos --release (version ${VERSION})"
else
  echo "==> flutter build macos --release (pubspec version)"
fi

mkdir -p "${OUT_DIR}"
rm -rf "${APP_DIR}"

pushd "${ROOT_DIR}/frontend" >/dev/null
flutter pub get
flutter "${flutter_build_args[@]}"
popd >/dev/null

# Flutter places the product under build/macos/Build/Products/Release/
SRC_APP=""
for candidate in \
  "${ROOT_DIR}/frontend/build/macos/Build/Products/Release/${APP_NAME}" \
  "${ROOT_DIR}/frontend/build/macos/Build/Products/Release/Fixora.app"
do
  if [[ -d "${candidate}" ]]; then
    SRC_APP="${candidate}"
    break
  fi
done

# Fallback: any .app in Release Products
if [[ -z "${SRC_APP}" ]]; then
  SRC_APP="$(find "${ROOT_DIR}/frontend/build/macos/Build/Products/Release" -maxdepth 1 -name '*.app' -print -quit 2>/dev/null || true)"
fi

if [[ -z "${SRC_APP}" || ! -d "${SRC_APP}" ]]; then
  echo "ERROR: Flutter macOS build did not produce an .app under frontend/build/macos/Build/Products/Release/" >&2
  exit 1
fi

cp -R "${SRC_APP}" "${APP_DIR}"

# Ensure Dock/Finder icon matches branding (Favicon → AppIcon.icns).
if [[ -f "${ROOT_DIR}/packaging/macos/AppIcon.icns" ]]; then
  mkdir -p "${APP_DIR}/Contents/Resources"
  cp "${ROOT_DIR}/packaging/macos/AppIcon.icns" "${APP_DIR}/Contents/Resources/AppIcon.icns"
fi

# Guard: App Sandbox must be off so the app reads the same
# ~/Library/Application Support/Fixora/ data as the legacy launcher.
if command -v codesign >/dev/null 2>&1; then
  ENTITLEMENTS_DUMP="$(mktemp)"
  if codesign -d --entitlements :- "${APP_DIR}" >"${ENTITLEMENTS_DUMP}" 2>/dev/null; then
    if grep -q "com.apple.security.app-sandbox" "${ENTITLEMENTS_DUMP}" && \
       /usr/libexec/PlistBuddy -c "Print :com.apple.security.app-sandbox" "${ENTITLEMENTS_DUMP}" 2>/dev/null | grep -qi "true"; then
      rm -f "${ENTITLEMENTS_DUMP}"
      echo "ERROR: Built app has App Sandbox enabled." >&2
      echo "  Fix frontend/macos/Runner/Release.entitlements (app-sandbox=false) and rebuild." >&2
      echo "  Sandbox hides existing repos under a Containers/ path." >&2
      exit 1
    fi
  fi
  rm -f "${ENTITLEMENTS_DUMP}"
fi

echo "Built Flutter macOS app at: ${APP_DIR}"
echo
echo "Next: copy backend to Contents/Resources/backend/ and rg to Contents/Resources/bin/rg"
echo "  (or run ./scripts/build_macos_dmg_all.sh)"
