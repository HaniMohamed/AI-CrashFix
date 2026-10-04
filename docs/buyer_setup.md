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

## Authentication

Fixora requires sign-in for all installs (local SQLite and shared Postgres). The HTTP API is protected except for health checks and the auth bootstrap/login endpoints.

### First launch

1. Launch Fixora when no users exist.
2. On the **Database** screen, choose **Local SQLite** or **Remote Postgres** and save (Postgres is tested before persisting).
3. On the **Sign in** screen, choose **Create administrator**.
4. Enter a username (and optional machine user ID to match existing repo data).
5. Copy the **one-time temporary password**, sign in, then set a permanent password (minimum 12 characters).
6. Complete the **Setup Wizard** (LLM, repo, optional integrations).

Store configuration is written to `store_bootstrap.json` under the data directory. Administrator accounts are created on that same store — configure the database before creating the first admin.

Passwords are stored with Argon2id hashing. Session tokens are stored server-side (SHA-256 of the bearer token); the raw token is kept only in the macOS Keychain via the app.

### Administrators

Admins have an **Administration** sidebar tab to:

- Add users (temporary password shown once)
- Block / unblock / delete users
- Reset a user to a new temporary password
- Tune session lifetime, lockout thresholds, minimum password length
- Toggle **repo data read-only** for all users

### Team Postgres

Each login account has a **machine user ID** (`tenant_user_id`) that scopes private repos and settings. Shared crash inventory remains per Firebase project. Use distinct machine user IDs per teammate when using shared Postgres.

## Path A — Packaged macOS app

1. Install `Fixora.app` from the DMG into Applications.
2. If Gatekeeper blocks: `xattr -cr "/Applications/Fixora.app"`.
3. Launch Fixora → complete the **Setup Wizard** (mock or production).
4. Optional: host apps can seed settings once via `AI_CRASH_FIX_ENV_FILE` (see [host_app_launch.md](host_app_launch.md)).

Data directory: `~/Library/Application Support/Fixora/`.

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
