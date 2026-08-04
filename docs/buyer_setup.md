# Fixora — Buyer setup guide

Fixora (formerly AI Crash Fix) turns Crashlytics crashes into reviewed code fixes, optional Jira issues, and draft GitLab merge requests for Flutter apps.

You do **not** need to maintain a root `.env` for day-to-day use. Configure via the **Setup Wizard** and **Settings**; values persist in SQLite (or shared Postgres).

## Configuration layers

| Layer | Use for | Where |
|-------|---------|--------|
| Bootstrap env | Store backend, DB URL, data dir, machine user id; CLI fallback for GCP | `.env` / `AI_CRASH_FIX_ENV_FILE` (rarely) |
| Settings store | LLM keys, Jira/GitLab servers + tokens | UI → `POST /api/settings` |
| Repo registry | Per Flutter app: GCP project ID, SA JSON, Crashlytics tables, Jira/GitLab project | Manage repositories |
| Client prefs | Theme, API base URL (web), dismissed tips | SharedPreferences |

Precedence for Crashlytics GCP: **repo → bootstrap env** (headless/CLI only). Product UI does not use a global BQ project or service account.

Internal env prefixes remain `AI_CRASH_FIX_*` for compatibility.

## Path A — Packaged macOS app

1. Install `Fixora.app` from the DMG into Applications.
2. If Gatekeeper blocks: `xattr -cr "/Applications/Fixora.app"`.
3. Launch Fixora → complete the **Setup Wizard** (mock or production).
4. Optional: host apps can seed settings once via `AI_CRASH_FIX_ENV_FILE` (see [host_app_launch.md](host_app_launch.md)).

Data directory: `~/Library/Application Support/Fixora/` (legacy installs may still use `AI Crash Fix/`).

## Path B — Source / local dev

```bash
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
# Optional bootstrap only:
cp .env.example .env   # fill LLM key OR leave empty and use the wizard

uvicorn app.api.server:app --reload --port 8000

cd frontend && flutter pub get
flutter run -d chrome --web-port 5173 \
  --dart-define=API_BASE_URL=http://localhost:8000
```

Prerequisites: Python 3.11+, ripgrep (`rg`), git, Flutter 3.24+.

## Path C — Team Postgres

```bash
cd infra/postgres
cp .env.example .env   # set POSTGRES_PASSWORD
docker compose up -d
```

Bootstrap (env file or process env):

```bash
AI_CRASH_FIX_CRASH_STORE_BACKEND=postgres
AI_CRASH_FIX_CRASH_DB_URL=postgresql://ai_crash_fix:PASSWORD@localhost:5432/ai_crash_fix
AI_CRASH_FIX_USER_ID=your.machine.id
```

Then open the UI and finish the wizard. Each teammate needs a distinct `AI_CRASH_FIX_USER_ID`.

## Mock-first checklist

1. Wizard → Quick demo  
2. Save Gemini or OpenAI API key  
3. Add any Flutter git repo (private repos need a token)  
4. Run mock batch (Skip Jira)  
5. Open Dashboard / Crashes / Live Run  

## Production checklist

1. Wizard → Production  
2. LLM key  
3. Optional Jira + GitLab globals  
4. Add Flutter repo with Firebase/GCP project ID, upload service account JSON, and Crashlytics dataset/tables (+ package/bundle IDs)  
5. Refresh repo to build Dart symbol index  
6. New Run with Mock off  

## Help in the app

Sidebar **Help** shows live readiness checks and short guides (Crashlytics tables, Jira auth, GitLab MRs, Postgres, troubleshooting).
