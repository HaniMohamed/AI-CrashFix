# Bundling (macOS desktop app + embedded backend)

This doc describes how to build and bundle the whole system into a macOS `.app`
that you can share with others.

## Prerequisites (builder machine)
- **macOS**
- **Flutter** installed (`flutter --version`)
- **Python** 3.11+ (this repo uses a venv under `.venv/`)
- Xcode command line tools (for macOS builds)

## 1) Build the backend binary (PyInstaller)

From repo root:

```bash
python -m venv .venv
source .venv/bin/activate
python -m pip install -U pip
pip install -r requirements.txt

./scripts/build_backend_macos.sh
```

Output:
- `dist/ai_crash_fix_backend/ai_crash_fix_backend`

## 2) Build the Flutter macOS app

```bash
cd frontend
flutter pub get
flutter config --enable-macos-desktop
flutter build macos --debug
cd ..
```

Output (debug example):
- `frontend/build/macos/Build/Products/Debug/ai_crash_fix_ui.app`

## 3) Stage the backend into the built .app bundle

This makes the app self-contained:

```bash
./scripts/stage_backend_into_built_macos_app.sh
```

This stages to:
- `.../ai_crash_fix_ui.app/Contents/Resources/backend/ai_crash_fix_backend`

If you have multiple builds, pass the app path explicitly:

```bash
./scripts/stage_backend_into_built_macos_app.sh "frontend/build/macos/Build/Products/Debug/ai_crash_fix_ui.app"
```

## 4) Share the app

Zip the `.app`:

```bash
ditto -c -k --sequesterRsrc --keepParent \
  "frontend/build/macos/Build/Products/Debug/ai_crash_fix_ui.app" \
  "ai_crash_fix_ui-macos.zip"
```

Send `ai_crash_fix_ui-macos.zip` to the recipient.

