"""Hermetic defaults for unit tests.

The developer/machine ``.env`` may set ``AI_CRASH_FIX_CRASH_STORE_BACKEND=postgres``.
Unit tests that use temp SQLite paths must not pick that up.
"""

from __future__ import annotations

import pytest


@pytest.fixture(autouse=True)
def _force_sqlite_app_store(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("AI_CRASH_FIX_CRASH_STORE_BACKEND", "sqlite")
    monkeypatch.setattr(
        "app.config.AI_CRASH_FIX_CRASH_STORE_BACKEND",
        "sqlite",
        raising=False,
    )
