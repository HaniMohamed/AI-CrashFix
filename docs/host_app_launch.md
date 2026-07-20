# Host app → AI Crash Fix launch guide

How the host macOS app should create config, install if needed, and open **AI Crash Fix**.

## Contract

| Item | Value |
|------|--------|
| App path | `/Applications/AI Crash Fix.app` |
| Env pointer | `AI_CRASH_FIX_ENV_FILE` = absolute path to a local `.env` file |
| Secrets | Put JWTs/keys **inside the env file only** — never pass them via `open --env` (ARG_MAX / "command too long") |
| DMG (optional) | Known path to `AI-Crash-Fix.dmg` for first-time install |

AI Crash Fix loads `AI_CRASH_FIX_ENV_FILE` at backend startup and applies the keys into Settings.

## Flow

```text
1. Write / update env file (tokens, provider, etc.)
2. If /Applications/AI Crash Fix.app is missing
     → open DMG (user drags app to Applications)
     → wait / prompt until app exists
3. Launch app with AI_CRASH_FIX_ENV_FILE set
```

## Step 1 — Create the env file

Write a file the user can read (e.g. `~/crash_fix_gosi_brain_conf.env`), `chmod 600`.

Example contents:

```bash
LLM_PROVIDER=gosi-brain
GOSI_BRAIN_AUTHORIZATION="Bearer <token>"
GOSI_BRAIN_API_KEY=<key>
GOSI_BRAIN_MODEL=gosi_brain_agent
GOSI_BRAIN_USER_ID=<user>
AI_CRASH_FIX_USER_ID=<user>
GOSI_BRAIN_COOKIE="<cookie>"
GOSI_BRAIN_STREAMING=off
# Optional shared Postgres (repos/settings/crashes):
# AI_CRASH_FIX_CRASH_STORE_BACKEND=postgres
# AI_CRASH_FIX_CRASH_DB_URL=postgresql://ai_crash_fix:password@host:5432/ai_crash_fix
```

`AI_CRASH_FIX_USER_ID` is the single identity for Postgres scoping and GOSI Brain `custom_session.user_id` (case-insensitive in the store). When it is set, `GOSI_BRAIN_USER_ID` is ignored. If omitted, the app falls back to `GOSI_BRAIN_USER_ID`.

Set `REPO_DATA_READONLY` in app settings (via `scripts/set_repo_data_readonly.py` or SQL) to make repos, settings, secrets, and index metadata view-only in the Manage repos dialog.

Host app responsibilities:

- Create/overwrite this file before each launch (or when tokens refresh).
- Use an **absolute** path (expand `~`).
- Do not put long secrets on the launch command line.

## Step 2 — Ensure the app is installed

```swift
let appURL = URL(fileURLWithPath: "/Applications/AI Crash Fix.app")
let installed = FileManager.default.fileExists(atPath: appURL.path)
```

If **not** installed:

1. Open the DMG (does **not** auto-install; user must drag to Applications):

```swift
NSWorkspace.shared.open(URL(fileURLWithPath: "/path/to/AI-Crash-Fix.dmg"))
```

2. Show UI: “Drag **AI Crash Fix** into **Applications**, then continue.”
3. Do not launch from the mounted DMG volume.
4. Optionally poll until `appURL` exists, then continue.

If Gatekeeper blocks first open, user may need right-click → **Open**, or:

```bash
xattr -cr "/Applications/AI Crash Fix.app"
```

## Step 3 — Launch with env file

Prefer `NSWorkspace` (equivalent to `open --env ...`):

```swift
import AppKit

func openAICrashFix(envFilePath: String) {
  let appURL = URL(fileURLWithPath: "/Applications/AI Crash Fix.app")
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
  -a "/Applications/AI Crash Fix.app"
```

## Important behaviors

- **Cold start only:** `AI_CRASH_FIX_ENV_FILE` is applied when a **new** process starts. If AI Crash Fix is already running, macOS may only activate it and ignore new env. For updated tokens: quit AI Crash Fix, rewrite the env file, then launch again — or document that users must quit first.
- **No deep links required** for this integration (no crash id / URL scheme).
- **One instance:** do not force a second instance (`createsNewApplicationInstance`); the embedded backend expects a single UI process.

## Minimal checklist for the host app

- [ ] Write env file with current tokens before launch
- [ ] Use absolute path in `AI_CRASH_FIX_ENV_FILE`
- [ ] Check `/Applications/AI Crash Fix.app`
- [ ] If missing → open DMG + instruct drag-to-Applications
- [ ] Launch via `NSWorkspace` + `OpenConfiguration.environment`
- [ ] Handle “already running” (quit + relaunch if tokens must refresh)
