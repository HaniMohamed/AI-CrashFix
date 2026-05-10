# macOS packaging (DMG)

This doc describes how to build `AI Crash Fix.app` and package it into a `.dmg`
for internal distribution on macOS **without requiring teammates to install
Python/Flutter/ripgrep**.

## What gets bundled

- **Launcher app**: starts backend on a free port and opens the browser UI
- **Backend executable**: PyInstaller-built `ai_crash_fix_backend`
- **Flutter Web assets**: `frontend/build/web/**` included into the backend bundle as `web/**`
- **ripgrep**: shipped as `Contents/Resources/bin/rg` and used via `AI_CRASH_FIX_RG_PATH`
- **Writable state**: stored under `~/Library/Application Support/AI Crash Fix/` (via `AI_CRASH_FIX_DATA_DIR`)

Git is assumed to be present on dev Macs (Xcode Command Line Tools).

## Launching with runtime config (from another app)

If you need to launch `AI Crash Fix.app` from another macOS app (e.g. Flutter) and pass LLM configuration at startup, you can use `open --args`.

The launcher maps these args into the backend environment variables (`LLM_PROVIDER`, `OPENAI_URL`, `OPENAI_MODEL`, `OPENAI_API_KEY`, etc.).

Example:

```bash
open -a "AI Crash Fix" --args \
  --llm-provider openai \
  --openai-url "https://api.openai.com/v1" \
  --openai-model "gpt-4o-mini" \
  --openai-api-key "sk-REPLACE_ME"
```

Notes:
- Passing API keys via `--args` can expose them in process listings. Prefer Keychain if this is a concern.
- The launcher writes logs under `~/Library/Application Support/AI Crash Fix/` and will redact secrets in `launcher.log`.

## Build steps (on your machine)

### One-command build (recommended)

```bash
# Optional: point to a specific ripgrep binary to bundle
# export RG_PATH="/opt/homebrew/bin/rg"
./scripts/build_macos_dmg_all.sh
```

Output:
- `dist/AI-Crash-Fix.dmg`

### 1) Build Flutter Web

```bash
cd frontend
flutter pub get
flutter build web --release
cd ..
```

### 2) Build backend bundle (PyInstaller)

```bash
./scripts/build_backend_pyinstaller.sh
```

Expected output:
- `dist/ai_crash_fix_backend/ai_crash_fix_backend`

### 3) Build the `.app` bundle (launcher)

```bash
./scripts/build_macos_app.sh
```

This creates:
- `dist/macos/AI Crash Fix.app`

### 4) Copy runtime binaries into the `.app`

```bash
APP="dist/macos/AI Crash Fix.app"

# backend (PyInstaller onedir bundle)
rm -rf "$APP/Contents/Resources/bin/ai_crash_fix_backend"
cp -R "dist/ai_crash_fix_backend" "$APP/Contents/Resources/bin/ai_crash_fix_backend"

# ripgrep (provide your own binary)
cp "/opt/homebrew/bin/rg" "$APP/Contents/Resources/bin/rg"
chmod +x "$APP/Contents/Resources/bin/"*
```

### 5) Create the DMG

```bash
./scripts/build_dmg.sh
```

Output:
- `dist/AI-Crash-Fix.dmg`

## Optional: codesigning (recommended)

Internal builds can work unsigned, but Gatekeeper warnings are common.
If you have a signing identity, sign the app bundle before building the DMG:

```bash
codesign --force --deep --sign "Developer ID Application: <Your Org>" "dist/macos/AI Crash Fix.app"
```

If you distribute outside the org or want the smoothest first-run experience,
also notarize the DMG/app.

