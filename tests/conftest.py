"""Hermetic defaults for unit tests.

The developer/machine ``.env`` may set ``AI_CRASH_FIX_CRASH_STORE_BACKEND=postgres``.
Unit tests that use temp SQLite paths must not pick that up.
"""

from __future__ import annotations

from pathlib import Path

import pytest


@pytest.fixture(autouse=True)
def _force_sqlite_app_store(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("AI_CRASH_FIX_CRASH_STORE_BACKEND", "sqlite")
    monkeypatch.setattr(
        "app.config.AI_CRASH_FIX_CRASH_STORE_BACKEND",
        "sqlite",
        raising=False,
    )


@pytest.fixture(autouse=True)
def _isolate_launch_env(monkeypatch: pytest.MonkeyPatch, tmp_path: Path) -> None:
    """Avoid picking up the developer machine ~/crash_fix_gosi_brain_conf.env."""
    monkeypatch.delenv("AI_CRASH_FIX_ENV_FILE", raising=False)
    monkeypatch.delenv("AI_CRASH_FIX_AUTO_LAUNCH_ENV", raising=False)
    monkeypatch.delenv("AI_CRASH_FIX_USER_ID", raising=False)
    home = tmp_path / "home"
    home.mkdir()
    monkeypatch.setenv("HOME", str(home))
