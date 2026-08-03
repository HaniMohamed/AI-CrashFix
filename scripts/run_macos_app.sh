#!/usr/bin/env bash
# Launch the macOS app with secrets from an env file (avoids "command too long"
# when GOSI_BRAIN_AUTHORIZATION JWT is huge).
#
# Usage:
#   ./scripts/run_macos_app.sh /path/to/gosi-launch.env
#   ./scripts/run_macos_app.sh /path/to/gosi-launch.env /path/to/AI\ Crash\ Fix.app
#
# The env file should contain KEY=VALUE lines (quote values with spaces), e.g.:
#   LLM_PROVIDER=gosi-brain
#   GOSI_BRAIN_AUTHORIZATION="Bearer eyJ..."
#   GOSI_BRAIN_API_KEY=...
#   GOSI_BRAIN_MODEL=gosi_brain_agent
#   GOSI_BRAIN_USER_ID=CR240821
#   GOSI_BRAIN_COOKIE="TS016ee342=..."
#   GOSI_BRAIN_STREAMING=off
#
set -euo pipefail

ENV_FILE="${1:-}"
APP_PATH="${2:-}"

if [[ -z "$ENV_FILE" ]]; then
  echo "Usage: $0 <env-file> [path-to-Fixora.app]" >&2
  exit 2
fi

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Env file not found: $ENV_FILE" >&2
  exit 1
fi

ENV_FILE="$(cd "$(dirname "$ENV_FILE")" && pwd)/$(basename "$ENV_FILE")"

if [[ -z "$APP_PATH" ]]; then
  ROOT="$(cd "$(dirname "$0")/.." && pwd)"
  APP_PATH="$ROOT/dist/macos/Fixora.app"
fi

BIN="$APP_PATH/Contents/MacOS/Fixora"
if [[ ! -x "$BIN" ]]; then
  # Some builds use underscore name from Swift launcher era
  if [[ -x "$APP_PATH/Contents/MacOS/AI_Crash_Fix" ]]; then
    BIN="$APP_PATH/Contents/MacOS/AI_Crash_Fix"
  else
    echo "App binary not found under: $APP_PATH/Contents/MacOS/" >&2
    exit 1
  fi
fi

# Short pointer only — backend loads the file (no JWT on argv).
export AI_CRASH_FIX_ENV_FILE="$ENV_FILE"
export AI_CRASH_FIX_AUTO_LAUNCH_ENV=1

# Also export keys into this process so Flutter inherits them for the child.
set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

exec "$BIN"
