from __future__ import annotations

import pytest

from app.services.user_context import (
    ai_crash_fix_user_id_raw,
    normalize_user_id,
    resolve_user_id,
)


def test_normalize_user_id_case_insensitive():
    assert normalize_user_id("CR231120") == "cr231120"
    assert normalize_user_id("  Cr231120  ") == "cr231120"
    assert normalize_user_id("") is None
    assert normalize_user_id(None) is None


def test_resolve_user_id_prefers_ai_crash_fix_user_id(monkeypatch):
    monkeypatch.setenv("AI_CRASH_FIX_USER_ID", "CR231120")
    monkeypatch.setattr("app.config.GOSI_BRAIN_USER_ID", "other")
    assert resolve_user_id() == "cr231120"
    assert ai_crash_fix_user_id_raw() == "CR231120"


def test_ai_crash_fix_user_id_ignores_gosi(monkeypatch):
    monkeypatch.setenv("AI_CRASH_FIX_USER_ID", "cr231120")
    monkeypatch.setattr("app.config.GOSI_BRAIN_USER_ID", "should_not_use")
    assert resolve_user_id() == "cr231120"


def test_resolve_user_id_falls_back_to_gosi(monkeypatch):
    monkeypatch.delenv("AI_CRASH_FIX_USER_ID", raising=False)
    monkeypatch.setattr("app.config.AI_CRASH_FIX_USER_ID", None)
    monkeypatch.setattr("app.config.GOSI_BRAIN_USER_ID", "AbC123")
    assert ai_crash_fix_user_id_raw() is None
    assert resolve_user_id() == "abc123"


def test_resolve_user_id_required_raises(monkeypatch):
    monkeypatch.delenv("AI_CRASH_FIX_USER_ID", raising=False)
    monkeypatch.setattr("app.config.AI_CRASH_FIX_USER_ID", None)
    monkeypatch.setattr("app.config.GOSI_BRAIN_USER_ID", None)
    with pytest.raises(ValueError, match="AI_CRASH_FIX_USER_ID"):
        resolve_user_id(required=True)


def test_effective_gosi_brain_uses_ai_crash_fix_user_id(monkeypatch, tmp_path):
    monkeypatch.setenv("AI_CRASH_FIX_CRASH_STORE_BACKEND", "sqlite")
    monkeypatch.setattr("app.config.AI_CRASH_FIX_CRASH_STORE_BACKEND", "sqlite")
    monkeypatch.setenv("AI_CRASH_FIX_USER_ID", "CR231120")
    monkeypatch.setattr("app.config.AI_CRASH_FIX_USER_ID", "CR231120")
    monkeypatch.setattr("app.config.GOSI_BRAIN_USER_ID", "ignored")
    db = tmp_path / "repo_registry.db"
    monkeypatch.setenv("AI_CRASH_FIX_REPO_REGISTRY_DB", str(db))

    from app.services.app_settings_store import AppSettingsStore
    from app.services.repo_registry_store import RepoRegistryStore
    from app.services.settings_resolver import SettingsResolver
    from app.services.sqlite_util import reset_schema_cache_for_tests

    reset_schema_cache_for_tests()
    AppSettingsStore.clear_shared_for_tests()
    RepoRegistryStore.clear_shared_for_tests()

    store = AppSettingsStore()
    store.set(k="GOSI_BRAIN_USER_ID", v="from_settings")
    gb = SettingsResolver().effective_gosi_brain()
    assert gb.get("user_id") == "CR231120"
