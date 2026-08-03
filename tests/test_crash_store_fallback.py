from __future__ import annotations

import os

from app.services.crash_store import (
    crash_store_backend_name,
    crash_store_health,
    ensure_crash_store_available,
    uses_postgres_crash_store,
)


def test_ensure_crash_store_falls_back_to_sqlite_when_postgres_unreachable(
    monkeypatch,
) -> None:
    monkeypatch.setenv("AI_CRASH_FIX_CRASH_STORE_BACKEND", "postgres")
    monkeypatch.setenv(
        "AI_CRASH_FIX_CRASH_DB_URL",
        "postgresql://ai_crash_fix:x@127.0.0.1:1/ai_crash_fix",
    )
    monkeypatch.delenv("AI_CRASH_FIX_CRASH_STORE_STRICT", raising=False)

    def _fail(*, connect_timeout: int = 3):
        del connect_timeout
        return False, "connection refused"

    monkeypatch.setattr(
        "app.services.crash_store.check_postgres_crash_store",
        _fail,
    )

    result = ensure_crash_store_available()
    assert result["ok"] is True
    assert result["backend"] == "sqlite"
    assert result["fallback_from"] == "postgres"
    assert crash_store_backend_name() == "sqlite"
    assert uses_postgres_crash_store() is False

    health = crash_store_health(force=True)
    assert health["backend"] == "sqlite"
    assert health["ok"] is True
    assert health.get("fallback_from") == "postgres"


def test_ensure_crash_store_strict_keeps_postgres_failure(monkeypatch) -> None:
    monkeypatch.setenv("AI_CRASH_FIX_CRASH_STORE_BACKEND", "postgres")
    monkeypatch.setenv(
        "AI_CRASH_FIX_CRASH_DB_URL",
        "postgresql://ai_crash_fix:x@127.0.0.1:1/ai_crash_fix",
    )
    monkeypatch.setenv("AI_CRASH_FIX_CRASH_STORE_STRICT", "1")

    monkeypatch.setattr(
        "app.services.crash_store.check_postgres_crash_store",
        lambda **_: (False, "connection refused"),
    )

    result = ensure_crash_store_available()
    assert result["ok"] is False
    assert result["backend"] == "postgres"
    assert os.environ["AI_CRASH_FIX_CRASH_STORE_BACKEND"] == "postgres"
