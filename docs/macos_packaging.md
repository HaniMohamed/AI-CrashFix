# macOS packaging (DMG)

This doc describes how to build `AI Crash Fix.app` and package it into a `.dmg`
for internal distribution on macOS **without requiring teammates to install
Python/Flutter/ripgrep**.

## What gets bundled

- **Flutter macOS app** (Dock icon, native window) — UI is Flutter desktop, not a browser
- **Backend executable**: PyInstaller-built `ai_crash_fix_backend` under
  `Contents/Resources/backend/ai_crash_fix_backend/`
- **ripgrep**: `Contents/Resources/bin/rg` (via `AI_CRASH_FIX_RG_PATH`)
- **Writable state**: `~/Library/Application Support/AI Crash Fix/` (`AI_CRASH_FIX_DATA_DIR`)

On launch the app picks a free loopback port, starts the embedded backend, waits
for `/api/health`, then talks to it over HTTP. **Closing the last window or
choosing Quit stops the backend** (SIGTERM, then SIGKILL if needed).

There is **no menubar tray** and the UI does **not** open in Safari/Chrome.

Git is assumed to be present on dev Macs (Xcode Command Line Tools).

### Legacy tray + browser launcher

`packaging/macos/launcher/` (Swift menubar / `LSUIElement`) is **unused** by the
DMG pipeline. Prefer the Flutter macOS Runner. Keep the folder only as reference
until you remove it.

## Bundle layout

```
AI Crash Fix.app/
  Contents/
    MacOS/AI Crash Fix
    Resources/
      AppIcon.icns
      backend/ai_crash_fix_backend/   # PyInstaller onedir
      bin/rg
```

## Dev workflows

**Web UI + external API (unchanged):**

```bash
uvicorn app.api.server:app --reload --port 8000
cd frontend && flutter run -d chrome --web-port 5173 --dart-define=API_BASE_URL=http://localhost:8000
```

**macOS UI + external API (no embedded backend):**

```bash
uvicorn app.api.server:app --reload --port 8000
cd frontend
AI_CRASH_FIX_USE_EMBEDDED_BACKEND=0 flutter run -d macos \
  --dart-define=API_BASE_URL=http://localhost:8000
```

Debug macOS runs without a staged binary automatically use the external API
(`http://localhost:8000` / prefs) instead of failing.

## Configuring LLM / crash store

Prefer the in-app **Settings** page (persisted by the backend).

For process environment overrides, launch the binary directly (so env is inherited):

```bash
export LLM_PROVIDER=openai
export OPENAI_URL="https://api.openai.com/v1"
export OPENAI_MODEL="gpt-4o-mini"
export OPENAI_API_KEY="sk-REPLACE_ME"
open "dist/macos/AI Crash Fix.app"
# or:
# "./dist/macos/AI Crash Fix.app/Contents/MacOS/AI Crash Fix"
```

On recent macOS you can also pass env via `open`:

```bash
open --env LLM_PROVIDER=openai --env OPENAI_API_KEY=sk-REPLACE_ME -a "AI Crash Fix"
```

Crash store:

- `AI_CRASH_FIX_CRASH_STORE_BACKEND` — `sqlite` (default) or `postgres`
- `AI_CRASH_FIX_CRASH_DB_URL` — Postgres URL when backend is `postgres`

Host Postgres with Docker Compose under [`infra/postgres/`](../infra/postgres/README.md).

## Shared crash store (Postgres)

The repo registry stays on local SQLite. Crash pipeline progress can use local
SQLite (default) or a team Postgres database keyed by Firebase project id.

Manual verification:

- Default SQLite: existing `db/*.db` files are untouched; batch dedup still works.
- Postgres: two clients with the same Firebase project see the same crashes and `already_processed` skips.
- Import: dry-run row counts match expectations; spot-check a known `crash_id` in Postgres.

## Build steps (on your machine)

### One-command build (recommended)

```bash
# Optional: point to a specific ripgrep binary to bundle
# export RG_PATH="/opt/homebrew/bin/rg"
./scripts/build_macos_dmg_all.sh
```

Output:

- `dist/macos/AI Crash Fix.app`
- `dist/AI-Crash-Fix.dmg`

### App icon

`./scripts/build_macos_dmg_all.sh` regenerates `packaging/macos/AppIcon.icns` and
the Flutter `AppIcon.appiconset` from `frontend/web/favicon.svg` when the
favicon is newer, so Dock/Finder keep the brand icon.

```bash
./scripts/macos_icon_from_svg.sh frontend/web/favicon.svg
```

Or from a custom 1024×1024 PNG:

```bash
./scripts/macos_make_icns.sh path/to/icon_1024.png
```

### Step-by-step

1) Flutter macOS release app:

```bash
./scripts/build_macos_app.sh
# → dist/macos/AI Crash Fix.app
```

2) Backend (PyInstaller):

```bash
./scripts/build_backend_pyinstaller.sh
# → dist/ai_crash_fix_backend/ai_crash_fix_backend
```

Flutter **web** assets are optional in the freeze (native macOS UI does not need them).

3) Inject backend + ripgrep:

```bash
APP="dist/macos/AI Crash Fix.app"
mkdir -p "$APP/Contents/Resources/backend" "$APP/Contents/Resources/bin"
rm -rf "$APP/Contents/Resources/backend/ai_crash_fix_backend"
cp -R "dist/ai_crash_fix_backend" "$APP/Contents/Resources/backend/ai_crash_fix_backend"
cp "/opt/homebrew/bin/rg" "$APP/Contents/Resources/bin/rg"
chmod +x "$APP/Contents/Resources/bin/rg"
```

4) DMG:

```bash
./scripts/build_dmg.sh
# → dist/AI-Crash-Fix.dmg
```

## Lifecycle

| Action | Backend |
|--------|---------|
| App launch | Spawn on free `127.0.0.1` port; wait for `/api/health` |
| Quit / close last window | Swift `AppDelegate` SIGTERM/SIGKILL synchronously; Dart also stops; backend parent-PID watchdog exits if the UI process dies |
| Debug without binary | Uses external API (`localhost:8000` / prefs) |

Override binary path: `AI_CRASH_FIX_BACKEND_PATH`.  
Disable embed: `AI_CRASH_FIX_USE_EMBEDDED_BACKEND=0`.

## Optional: codesigning (recommended)

Internal builds can work unsigned, but Gatekeeper warnings are common.
If you have a signing identity, sign the app bundle before building the DMG:

```bash
codesign --force --deep --sign "Developer ID Application: <Your Org>" "dist/macos/AI Crash Fix.app"
```

If you distribute outside the org or want the smoothest first-run experience,
also notarize the DMG/app.

## DMG "installer UI" customization

`./scripts/build_dmg.sh` creates a compact drag-to-install DMG window:

- sets window size and icon positions (app on the left, `Applications` on the right)
- applies a minimal neutral background from `packaging/macos/dmg_background.svg`

Notes:

- The background is rasterized via macOS Quick Look (`qlmanage`) during the DMG build.
- If customization fails (e.g. in a headless environment), the script still produces a valid DMG, just without the customized window/background.
