# macOS packaging (DMG)

This doc describes how to build `Fixora.app` and package it into a `.dmg`
for internal distribution on macOS **without requiring teammates to install
Python/Flutter/ripgrep**.

## What gets bundled

- **Flutter macOS app** (Dock icon, native window) — UI is Flutter desktop, not a browser
- **Backend executable**: PyInstaller-built `ai_crash_fix_backend` under
  `Contents/Resources/backend/ai_crash_fix_backend/`
- **ripgrep**: `Contents/Resources/bin/rg` (via `AI_CRASH_FIX_RG_PATH`)
- **Writable state**: `~/Library/Application Support/Fixora/` (`AI_CRASH_FIX_DATA_DIR`)
  — same folder as the previous menubar launcher (repos, settings, crash DBs, clones)

App Sandbox is **disabled** on purpose. A sandboxed build stores data under
`~/Library/Containers/com.internal.aicrashfix/...` and looks like a fresh install
with no repos.

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
Fixora.app/
  Contents/
    MacOS/Fixora
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
open "dist/macos/Fixora.app"
# or:
# "./dist/macos/Fixora.app/Contents/MacOS/Fixora"
```

On recent macOS you can also pass env via `open` (short values only — a full
JWT often triggers **"command too long"** / `ARG_MAX`):

```bash
open --env LLM_PROVIDER=openai --env OPENAI_API_KEY=sk-REPLACE_ME -a "Fixora"
```

### GOSI Brain (recommended: env file)

Put long secrets in a local file (not on the command line):

```bash
# ~/gosi-launch.env  (chmod 600)
LLM_PROVIDER=gosi-brain
GOSI_BRAIN_AUTHORIZATION="Bearer eyJ..."
GOSI_BRAIN_API_KEY=...
GOSI_BRAIN_MODEL=gosi_brain_agent
GOSI_BRAIN_USER_ID=CR240821
GOSI_BRAIN_COOKIE="TS016ee342=..."
GOSI_BRAIN_STREAMING=off
```

Copy `GOSI_BRAIN_COOKIE` from a working Postman/curl `Cookie` header (F5 `TS*` cookies rotate; refresh on HTTP 401).

Then launch with the helper (exports the file into the process and sets
`AI_CRASH_FIX_ENV_FILE` so the backend persists Settings):

```bash
./scripts/run_macos_app.sh ~/gosi-launch.env
# or with an explicit .app path:
./scripts/run_macos_app.sh ~/gosi-launch.env "dist/macos/Fixora.app"
```

Alternatively:

```bash
export AI_CRASH_FIX_ENV_FILE=~/gosi-launch.env
"./dist/macos/Fixora.app/Contents/MacOS/Fixora"
```

Crash store:

- `AI_CRASH_FIX_CRASH_STORE_BACKEND` — `sqlite` (default) or `postgres`
- `AI_CRASH_FIX_CRASH_DB_URL` — Postgres URL when backend is `postgres`

Host Postgres with Docker Compose under [`infra/postgres/`](../infra/postgres/README.md).

## Shared app store (Postgres)

When `AI_CRASH_FIX_CRASH_STORE_BACKEND=postgres`, **crashes, repos, settings,
app_state, and repo_indexes** all live in the shared Postgres database
(`AI_CRASH_FIX_CRASH_DB_URL`). Repos/settings are scoped by
`AI_CRASH_FIX_USER_ID` (case-insensitive; when set, `GOSI_BRAIN_USER_ID` is ignored).
Crash inventory stays shared by Firebase project; rows record
`created_by_user_id` for audit.

Set `REPO_DATA_READONLY` in app settings (per user on Postgres) to block UI/API writes to repos,
settings, secrets, and index metadata. Use `scripts/set_repo_data_readonly.py true|false`.

Default remains local SQLite under `db/` when backend is `sqlite`.

Manual verification:

- Default SQLite: existing `db/*.db` files are untouched; batch dedup still works.
- Postgres: two clients with the same Firebase project see the same crashes and `already_processed` skips; each client's repos/settings are private to their user id.
- Import: `scripts/migrate_app_store_to_postgres.py --user-id … --data-dir …` dry-run row counts match expectations.

## Build steps (on your machine)

### One-command build (recommended)

```bash
# Optional: point to a specific ripgrep binary to bundle
# export RG_PATH="/opt/homebrew/bin/rg"
./scripts/build_macos_dmg_all.sh
```

Output:

- `dist/macos/Fixora.app`
- `dist/Fixora.dmg`

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
# → dist/macos/Fixora.app
```

2) Backend (PyInstaller):

```bash
./scripts/build_backend_pyinstaller.sh
# → dist/ai_crash_fix_backend/ai_crash_fix_backend
```

Flutter **web** assets are optional in the freeze (native macOS UI does not need them).

3) Inject backend + ripgrep, then **re-sign** (required):

```bash
APP="dist/macos/Fixora.app"
mkdir -p "$APP/Contents/Resources/backend" "$APP/Contents/Resources/bin"
rm -rf "$APP/Contents/Resources/backend/ai_crash_fix_backend"
ditto "dist/ai_crash_fix_backend" "$APP/Contents/Resources/backend/ai_crash_fix_backend"
ditto "/opt/homebrew/bin/rg" "$APP/Contents/Resources/bin/rg"
chmod +x "$APP/Contents/Resources/bin/rg"
./scripts/resign_macos_app.sh "$APP"
```

Flutter seals the app **before** backend injection. Skipping re-sign leaves an
invalid signature: Gatekeeper then blocks the embedded backend after you drag
the app from the DMG into `/Applications` (UI shows API offline).

4) DMG:

```bash
./scripts/build_dmg.sh
# → dist/Fixora.dmg
```

## Install from DMG

1. Open `Fixora.dmg`
2. Drag **Fixora.app** into **Applications** (do not run it from the DMG)
3. Launch from `/Applications`
4. If macOS blocks the first open: right-click → **Open**, or clear quarantine:

```bash
xattr -cr "/Applications/Fixora.app"
```

Confirm the install includes the backend:

```bash
ls -la "/Applications/Fixora.app/Contents/Resources/backend/ai_crash_fix_backend/ai_crash_fix_backend"
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

`build_macos_dmg_all.sh` always **adhoc re-signs** after injecting the backend
(`scripts/resign_macos_app.sh`). That is enough for most internal installs.

If you have a Developer ID identity, sign before building the DMG (replaces adhoc):

```bash
codesign --force --deep --sign "Developer ID Application: <Your Org>" \
  --entitlements frontend/macos/Runner/Release.entitlements \
  "dist/macos/Fixora.app"
codesign --verify --deep --strict "dist/macos/Fixora.app"
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
