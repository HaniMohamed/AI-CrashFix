from __future__ import annotations

from pathlib import Path

from app.services.app_settings_store import AppSettingsStore
from app.services.repo_registry_store import RepoRegistryStore
from app.services.settings_resolver import SettingsResolver
from app.services.sqlite_util import reset_schema_cache_for_tests


def test_app_settings_store_is_singleton_per_path(tmp_path: Path, monkeypatch) -> None:
    reset_schema_cache_for_tests()
    AppSettingsStore.clear_shared_for_tests()
    db = tmp_path / "repo_registry.db"
    monkeypatch.setenv("AI_CRASH_FIX_REPO_REGISTRY_DB", str(db))

    a = AppSettingsStore()
    b = AppSettingsStore()
    assert a is b
    a.set(k="LLM_PROVIDER", v="gosi-brain")
    assert b.get(k="LLM_PROVIDER") == "gosi-brain"


def test_settings_resolver_reads_settings_from_cache(tmp_path: Path, monkeypatch) -> None:
    reset_schema_cache_for_tests()
    AppSettingsStore.clear_shared_for_tests()
    RepoRegistryStore.clear_shared_for_tests()
    db = tmp_path / "repo_registry.db"
    monkeypatch.setenv("AI_CRASH_FIX_REPO_REGISTRY_DB", str(db))
    monkeypatch.setenv("LLM_PROVIDER", "gemini")

    store = AppSettingsStore()
    store.set(k="LLM_PROVIDER", v="gosi-brain")
    store.set(k="GOSI_BRAIN_MODEL", v="gosi_brain_agent")

    r = SettingsResolver()
    assert r.effective_llm_provider() == "gosi-brain"
    assert r.effective_gosi_brain().get("model") == "gosi_brain_agent"
