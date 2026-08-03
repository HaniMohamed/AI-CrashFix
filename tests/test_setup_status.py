from __future__ import annotations

import os

import pytest


@pytest.fixture()
def sqlite_backend(monkeypatch, tmp_path):
    monkeypatch.setenv("AI_CRASH_FIX_CRASH_STORE_BACKEND", "sqlite")
    monkeypatch.setenv("AI_CRASH_FIX_REPO_REGISTRY_DB", str(tmp_path / "registry.db"))
    monkeypatch.delenv("AI_CRASH_FIX_CRASH_DB_URL", raising=False)
    # Force config module values used by uses_postgres_crash_store
    import app.config as cfg
    import app.services.app_settings_store as app_settings_store
    import app.services.repo_registry_store as repo_registry_store

    monkeypatch.setattr(cfg, "AI_CRASH_FIX_CRASH_STORE_BACKEND", "sqlite")
    monkeypatch.setattr(cfg, "AI_CRASH_FIX_CRASH_DB_URL", None)
    AppSettingsStore = app_settings_store.AppSettingsStore
    RepoRegistryStore = repo_registry_store.RepoRegistryStore
    AppSettingsStore.clear_shared_for_tests()
    RepoRegistryStore.clear_shared_for_tests()
    yield tmp_path
    AppSettingsStore.clear_shared_for_tests()
    RepoRegistryStore.clear_shared_for_tests()


def test_setup_status_welcome_when_empty(sqlite_backend):
    from app.services.setup_status import compute_setup_status

    status = compute_setup_status()
    assert status["product"] == "Fixora"
    assert status["setup_complete"] is False
    assert status["next_step"] in ("welcome", "llm")
    assert "llm" in {c["id"] for c in status["checks"]}


def test_setup_status_legacy_complete_with_llm_and_repo(sqlite_backend):
    from app.services.app_settings_store import AppSettingsStore
    from app.services.repo_registry_store import RepoRegistryStore
    from app.services.setup_status import compute_setup_status

    AppSettingsStore().set(k="LLM_PROVIDER", v="gemini")
    AppSettingsStore().set(k="GOOGLE_API_KEY", v="test-key")
    RepoRegistryStore().upsert_repo(
        name="Demo",
        repo_url="https://example.com/org/app.git",
        repo_ref="main",
        firebase_project_id="demo",
    )
    status = compute_setup_status()
    assert status["setup_complete"] is True
    assert status["next_step"] == "done"
    assert status["repo_count"] >= 1
