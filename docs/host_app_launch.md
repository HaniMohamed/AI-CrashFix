# Host app → Fixora launch guide

How the host macOS app should create config, install if needed, and open **Fixora**.

## Contract

| Item | Value |
|------|--------|
| App path | `/Applications/Fixora.app` |
| Env pointer | `AI_CRASH_FIX_ENV_FILE` = absolute path to a local `.env` file |
| Secrets | Put JWTs/keys **inside the env file only** — never pass them via `open --env` (ARG_MAX / "command too long") |
| DMG (optional) | Known path to `Fixora.dmg` for first-time install |

Fixora loads `AI_CRASH_FIX_ENV_FILE` at backend startup and applies the keys into Settings.

## Flow

```text
1. Write / update env file (tokens, provider, etc.)
2. If /Applications/Fixora.app is missing
     → open DMG (user drags app to Applications)
     → wait / prompt until app exists
3. Launch app with AI_CRASH_FIX_ENV_FILE set
```

## Step 1 — Create the env file

Write a file the user can read (e.g. `~/crash_fix_gosi_brain_conf.env`), `chmod 600`.

Example contents (matches `~/crash_fix_gosi_brain_conf.env`; replace `<user>`, `<password>`, and token placeholders):

```bash
# GOSI Brain launch env (chmod 600)
# Launch:
#   open --env AI_CRASH_FIX_ENV_FILE="$HOME/crash_fix_gosi_brain_conf.env" -a "Fixora"
# Or:
#   ./scripts/run_macos_app.sh "$HOME/crash_fix_gosi_brain_conf.env"
#
# Refresh GOSI_BRAIN_COOKIE from a working Postman/curl Cookie header when you get HTTP 401.

AI_CRASH_FIX_CRASH_STORE_BACKEND=postgres
AI_CRASH_FIX_CRASH_DB_URL=postgresql://ai_crash_fix:<password>@localhost:5432/ai_crash_fix

# Self-signed corporate TLS (jira.gosi.ins / gitlab.gosi.ins)
JIRA_VERIFY_SSL=false
GITLAB_VERIFY_SSL=false
# Jira Data Center personal access token (not Cloud Basic email:token)
JIRA_AUTH=bearer
# DE Bug required custom field: Concerned DE Team (see bug_examples.csv)
JIRA_CREATE_FIELDS={"customfield_11404":{"value":"Individual App + Taqdeer"}}

LLM_PROVIDER=gosi-brain
GOSI_BRAIN_URL=https://intsol.gosi.gov.sa/v1/iwaiapiproxy/chat/completions
GOSI_BRAIN_MODEL=thinking
GOSI_BRAIN_USER_ID=<user>
GOSI_BRAIN_API_KEY=<api-key>
GOSI_BRAIN_COOKIE="<cookie>"
GOSI_BRAIN_STREAMING=on
GOSI_BRAIN_SEND_OAUTH_DOMAIN=false
GOSI_BRAIN_AUTHORIZATION="Bearer <jwt>"
AI_CRASH_FIX_USER_ID=<user>
```

`AI_CRASH_FIX_USER_ID` scopes Postgres / app-store rows (case-insensitive). `GOSI_BRAIN_USER_ID` is only for GOSI Brain `custom_session.user_id` — set both when launching from CodeFaster (they may be the same value, but they are not interchangeable).

Set `REPO_DATA_READONLY` in app settings (via `scripts/set_repo_data_readonly.py` or SQL) to make repos, settings, secrets, and index metadata view-only in the Manage repos dialog.

Host app responsibilities:

- Create/overwrite this file before each launch (or when tokens refresh).
- Use an **absolute** path (expand `~`).
- Do not put long secrets on the launch command line.

## Step 2 — Ensure the app is installed

```swift
let appURL = URL(fileURLWithPath: "/Applications/Fixora.app")
let installed = FileManager.default.fileExists(atPath: appURL.path)
```

If **not** installed:

1. Open the DMG (does **not** auto-install; user must drag to Applications):

```swift
NSWorkspace.shared.open(URL(fileURLWithPath: "/path/to/Fixora.dmg"))
```

2. Show UI: “Drag **Fixora** into **Applications**, then continue.”
3. Do not launch from the mounted DMG volume.
4. Optionally poll until `appURL` exists, then continue.

If Gatekeeper blocks first open, user may need right-click → **Open**, or:

```bash
xattr -cr "/Applications/Fixora.app"
```

## Step 3 — Launch with env file

Prefer `NSWorkspace` (equivalent to `open --env ...`):

```swift
import AppKit

func openAICrashFix(envFilePath: String) {
  let appURL = URL(fileURLWithPath: "/Applications/Fixora.app")
  guard FileManager.default.fileExists(atPath: appURL.path) else {
    // Open DMG / prompt install — see Step 2
    return
  }

  let config = NSWorkspace.OpenConfiguration()
  config.activates = true
  config.environment = [
    "AI_CRASH_FIX_ENV_FILE": (envFilePath as NSString).expandingTildeInPath
  ]

  NSWorkspace.shared.openApplication(at: appURL, configuration: config) { _, error in
    if let error {
      // surface to user
      print(error.localizedDescription)
    }
  }
}
```

Shell equivalent (for debugging):

```bash
open --env AI_CRASH_FIX_ENV_FILE="$HOME/crash_fix_gosi_brain_conf.env" \
  -a "/Applications/Fixora.app"
```

## Important behaviors

- **Standalone defaults:** The macOS app does **not** auto-load `~/crash_fix_gosi_brain_conf.env`. Configure LLM credentials in **Settings**, or pass an explicit `AI_CRASH_FIX_ENV_FILE` when launching.
- **No CodeFaster UI gate:** Missing or expired GOSI Brain tokens do not hard-block the app. Runs fail with a normal API error until credentials are set in Settings (or another LLM provider is selected).
- **Cold start only:** `AI_CRASH_FIX_ENV_FILE` is applied when a **new** process starts. If Fixora is already running, macOS may only activate it and ignore new env. For updated tokens: quit Fixora, rewrite the env file, then launch again — or document that users must quit first.
- **No deep links required** for optional host-app launch (no crash id / URL scheme).
- **One instance:** do not force a second instance (`createsNewApplicationInstance`); the embedded backend expects a single UI process.

## Minimal checklist for the host app

- [ ] Write env file with current tokens before launch
- [ ] Use absolute path in `AI_CRASH_FIX_ENV_FILE`
- [ ] Check `/Applications/Fixora.app`
- [ ] If missing → open DMG + instruct drag-to-Applications
- [ ] Launch via `NSWorkspace` + `OpenConfiguration.environment`
- [ ] Handle “already running” (quit + relaunch if tokens must refresh)
