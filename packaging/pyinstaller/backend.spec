from __future__ import annotations

# PyInstaller spec for the AI Crash Fix FastAPI backend.
#
# Build:
#   python -m PyInstaller packaging/pyinstaller/backend.spec
#
# Output binary:
#   dist/ai_crash_fix_backend

import sys
from pathlib import Path

from PyInstaller.utils.hooks import collect_submodules

# NOTE: PyInstaller executes spec files via `exec()` and does not guarantee `__file__`.
# We require running the build from the repo root so we can resolve paths reliably.
PROJECT_ROOT = Path.cwd().resolve()

hiddenimports = []
hiddenimports += collect_submodules("app")

datas = []

# Bundle Flutter Web build output (served by FastAPI when frozen).
# Expected path: frontend/build/web/index.html
web_root = PROJECT_ROOT / "frontend" / "build" / "web"
if (web_root / "index.html").is_file():
    datas.append((str(web_root), "web"))

a = Analysis(
    [str(PROJECT_ROOT / "backend_main.py")],
    pathex=[str(PROJECT_ROOT)],
    binaries=[],
    datas=datas,
    hiddenimports=hiddenimports,
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    # PyInstaller cannot freeze an env with multiple Qt bindings installed.
    # Our backend doesn't use Qt; exclude all Qt bindings/hooks that might be present
    # in a developer machine's global environment.
    excludes=[
        "PyQt5",
        "PyQt6",
        "PySide2",
        "PySide6",
        "qtpy",
        "sip",
        "shiboken2",
        "shiboken6",
    ],
    win_no_prefer_redirects=False,
    win_private_assemblies=False,
    cipher=None,
    noarchive=False,
)

pyz = PYZ(a.pure, a.zipped_data, cipher=None)

exe = EXE(
    pyz,
    a.scripts,
    [],
    exclude_binaries=True,
    name="ai_crash_fix_backend",
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,
    console=True,
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
)

coll = COLLECT(
    exe,
    a.binaries,
    a.zipfiles,
    a.datas,
    strip=False,
    upx=True,
    upx_exclude=[],
    name="ai_crash_fix_backend",
)

