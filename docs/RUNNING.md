# Running the bundled macOS app (recipient guide)

This doc describes how to run the received macOS app bundle on a machine that
did not build it.

## Requirements (recipient machine)
- **macOS**
- No Python/Flutter installs required (backend is embedded)

## 1) Unzip

Double-click the zip you received (or unzip via Finder). You should get:
- `ai_crash_fix_ui.app`

## 2) macOS security prompt (Gatekeeper)

Because this is a locally-built app (not notarized), macOS may block it.

If you see “can’t be opened because Apple cannot check it”:
- System Settings → Privacy & Security → scroll down → **Open Anyway**

Or:
- Right click the app → **Open** → confirm

## 3) Run

Open `ai_crash_fix_ui.app`.

On first launch:
- the app starts an embedded backend on `127.0.0.1` using a random free port
- the UI waits for `/api/health` to become OK

## 4) Data location (SQLite)

The backend stores the crash database in:

- If sandboxed (default):\n  `~/Library/Containers/com.example.aiCrashFixUi/Data/Library/Application Support/AI Crash Fix/<project>_crash_store.db`\n+- If sandbox is disabled:\n  `~/Library/Application Support/AI Crash Fix/<project>_crash_store.db`

(where `<project>` is your configured Crashlytics BigQuery project id.)

## 5) Optional configuration

### Recommended: drop a `.env` file (no Terminal needed)

Create this file on the recipient machine:

- If sandboxed (default):\n  `~/Library/Containers/com.example.aiCrashFixUi/Data/Library/Application Support/AI Crash Fix/.env`\n+- If sandbox is disabled:\n  `~/Library/Application Support/AI Crash Fix/.env`

Then put your normal backend config inside it (same keys as the repo `.env`), e.g.:

```bash
REPO_ROOT=/absolute/path/to/target/repo
MAIN_BRANCH=main

LLM_PROVIDER=gemini
GOOGLE_API_KEY=...
GEMINI_MODEL=gemini-2.5-flash
```

Now you can launch the app normally (Finder / Dock) and it will pick up the config.

### Advanced: environment variables (Terminal launch)

You can also override defaults using environment variables when launching from Terminal:

- `AI_CRASH_FIX_BACKEND_PATH`: explicit path to the backend binary (normally not needed)
- `AI_CRASH_FIX_DB_PATH`: explicit path to the SQLite DB
- `AI_CRASH_FIX_USE_EMBEDDED_BACKEND=0`: disable embedded backend (use external)
- `AI_CRASH_FIX_ENV_FILE`: explicit path to a `.env` file (highest priority)

Example:

```bash
AI_CRASH_FIX_DB_PATH="$HOME/Library/Application Support/AI Crash Fix/custom.db" \
open /path/to/ai_crash_fix_ui.app
```

## Troubleshooting

- **Stuck on “starting backend”**: the embedded backend bundle is missing from the `.app`.\n  It must exist at:\n  `ai_crash_fix_ui.app/Contents/Resources/backend/ai_crash_fix_backend/` (folder)\n  and include:\n  - `ai_crash_fix_backend` (executable)\n  - `_internal/` (PyInstaller runtime)\n+- **Port errors**: quit the app and reopen; it picks another free port.\n+- **Backend disabled**: ensure `AI_CRASH_FIX_USE_EMBEDDED_BACKEND` is not set to `0`.\n+- **Config not picked up**: double-check you placed `.env` in the sandbox container path above.\n 

