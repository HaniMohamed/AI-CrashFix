"""Tests for connectivity check helpers."""

from __future__ import annotations

import pytest

from app.services.connectivity_checks import check_store_connection


def test_check_store_connection_sqlite_ok():
    result = check_store_connection(backend="sqlite")
    assert result["ok"] is True
    assert "SQLite" in result["message"]


def test_check_store_connection_postgres_missing_url(monkeypatch):
    monkeypatch.delenv("AI_CRASH_FIX_CRASH_DB_URL", raising=False)
    with pytest.raises(ValueError, match="db_url is required"):
        check_store_connection(backend="postgres", user_id="alice")
