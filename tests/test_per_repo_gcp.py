from __future__ import annotations

import json

import pytest


@pytest.fixture()
def sqlite_backend(monkeypatch, tmp_path):
    monkeypatch.setenv("AI_CRASH_FIX_CRASH_STORE_BACKEND", "sqlite")
    monkeypatch.setenv("AI_CRASH_FIX_REPO_REGISTRY_DB", str(tmp_path / "registry.db"))
    monkeypatch.delenv("AI_CRASH_FIX_CRASH_DB_URL", raising=False)
    import app.config as cfg
    import app.services.app_settings_store as app_settings_store
    import app.services.repo_registry_store as repo_registry_store

    monkeypatch.setattr(cfg, "AI_CRASH_FIX_CRASH_STORE_BACKEND", "sqlite")
    monkeypatch.setattr(cfg, "AI_CRASH_FIX_CRASH_DB_URL", None)
    monkeypatch.setattr(cfg, "BQ_PROJECT_ID", None)
    monkeypatch.setattr(cfg, "GOOGLE_APPLICATION_CREDENTIALS", None)
    monkeypatch.setattr(
        cfg, "WORKSPACE_PROJECTS_DIR", str(tmp_path / "workspace_projects")
    )
    AppSettingsStore = app_settings_store.AppSettingsStore
    RepoRegistryStore = repo_registry_store.RepoRegistryStore
    AppSettingsStore.clear_shared_for_tests()
    RepoRegistryStore.clear_shared_for_tests()
    yield tmp_path
    AppSettingsStore.clear_shared_for_tests()
    RepoRegistryStore.clear_shared_for_tests()


def test_repo_column_and_has_flag(sqlite_backend, tmp_path):
    from app.services.repo_registry_store import RepoRegistryStore

    store = RepoRegistryStore()
    entry = store.upsert_repo(
        name="App",
        repo_url="https://example.com/org/app.git",
        repo_ref="main",
        firebase_project_id="proj-a",
    )
    assert entry.has_google_application_credentials is False
    cred = tmp_path / "sa.json"
    cred.write_text('{"type":"service_account"}', encoding="utf-8")
    updated = store.set_google_application_credentials(entry.repo_key, str(cred))
    assert updated.has_google_application_credentials is True
    assert store.get_google_application_credentials(entry.repo_key) == str(cred)

    # Upsert must preserve credentials path.
    again = store.upsert_repo(
        name="App",
        repo_url="https://example.com/org/app.git",
        repo_ref="main",
        firebase_project_id="proj-a",
    )
    assert again.has_google_application_credentials is True
    assert store.get_google_application_credentials(again.repo_key) == str(cred)


def test_resolver_repo_creds_win_over_env_and_ignore_app_settings(
    sqlite_backend, tmp_path, monkeypatch
):
    import app.config as cfg
    from app.services.app_settings_store import AppSettingsStore
    from app.services.repo_registry_store import RepoRegistryStore
    from app.services.settings_resolver import SettingsResolver

    env_cred = tmp_path / "env_sa.json"
    env_cred.write_text('{"type":"service_account"}', encoding="utf-8")
    repo_cred = tmp_path / "repo_sa.json"
    repo_cred.write_text('{"type":"service_account"}', encoding="utf-8")
    stale_global = tmp_path / "global_sa.json"
    stale_global.write_text('{"type":"service_account"}', encoding="utf-8")

    monkeypatch.setattr(cfg, "GOOGLE_APPLICATION_CREDENTIALS", str(env_cred))
    monkeypatch.setattr(cfg, "BQ_PROJECT_ID", "env-project")
    AppSettingsStore().set(k="GOOGLE_APPLICATION_CREDENTIALS", v=str(stale_global))
    AppSettingsStore().set(k="BQ_PROJECT_ID", v="settings-project")

    store = RepoRegistryStore()
    entry = store.upsert_repo(
        name="App",
        repo_url="https://example.com/org/app.git",
        repo_ref="main",
        firebase_project_id="repo-project",
    )
    store.set_google_application_credentials(entry.repo_key, str(repo_cred))

    resolver = SettingsResolver()
    assert (
        resolver.effective_google_application_credentials(repo_key=entry.repo_key)
        == str(repo_cred)
    )
    assert resolver.effective_firebase_project_id(repo_key=entry.repo_key) == "repo-project"

    # No repo key → env only (not app_settings).
    assert resolver.effective_google_application_credentials(repo_key=None) == str(
        env_cred
    )
    assert resolver.effective_firebase_project_id(repo_key=None) == "env-project"

    # Repo without creds falls back to env, not app_settings.
    bare = store.upsert_repo(
        name="Bare",
        repo_url="https://example.com/org/bare.git",
        repo_ref="main",
    )
    assert resolver.effective_google_application_credentials(
        repo_key=bare.repo_key
    ) == str(env_cred)
    assert resolver.effective_firebase_project_id(repo_key=bare.repo_key) == "env-project"


def test_save_repo_google_credentials_writes_scoped_path(sqlite_backend, tmp_path):
    from pathlib import Path

    from app.services.repo_gcp_credentials import save_repo_google_credentials
    from app.services.repo_registry_store import RepoRegistryStore

    store = RepoRegistryStore()
    entry = store.upsert_repo(
        name="App",
        repo_url="https://example.com/org/app.git",
        repo_ref="main",
        firebase_project_id="proj-a",
    )
    raw = json.dumps(
        {"type": "service_account", "project_id": "proj-a", "client_email": "a@b.c"}
    ).encode("utf-8")
    updated, path = save_repo_google_credentials(repo_key=entry.repo_key, raw=raw)
    assert updated.has_google_application_credentials is True
    assert "_credentials" in path
    assert Path(path).is_file()
    assert store.get_google_application_credentials(entry.repo_key) == path


def test_migration_seeds_empty_repos_from_global(sqlite_backend, tmp_path, monkeypatch):
    import app.config as cfg
    from app.services.app_settings_store import AppSettingsStore
    from app.services.gcp_repo_migration import migrate_global_gcp_to_repos
    from app.services.repo_registry_store import RepoRegistryStore

    cred = tmp_path / "legacy_sa.json"
    cred.write_text('{"type":"service_account"}', encoding="utf-8")
    AppSettingsStore().set(k="BQ_PROJECT_ID", v="legacy-project")
    AppSettingsStore().set(k="GOOGLE_APPLICATION_CREDENTIALS", v=str(cred))
    monkeypatch.setattr(cfg, "BQ_PROJECT_ID", None)
    monkeypatch.setattr(cfg, "GOOGLE_APPLICATION_CREDENTIALS", None)

    store = RepoRegistryStore()
    entry = store.upsert_repo(
        name="App",
        repo_url="https://example.com/org/app.git",
        repo_ref="main",
    )
    assert not (entry.firebase_project_id or "").strip()
    assert entry.has_google_application_credentials is False

    result = migrate_global_gcp_to_repos(force=True)
    assert result["repos_updated"] == 1
    refreshed = store.get_repo(entry.repo_key)
    assert refreshed is not None
    assert refreshed.firebase_project_id == "legacy-project"
    assert refreshed.has_google_application_credentials is True
    assert store.get_google_application_credentials(entry.repo_key) == str(cred)

    # Idempotent via flag.
    again = migrate_global_gcp_to_repos(force=False)
    assert again["skipped"] == 1


def test_setup_status_production_requires_repo_gcp(sqlite_backend, tmp_path):
    from app.services.app_settings_store import AppSettingsStore
    from app.services.repo_registry_store import RepoRegistryStore
    from app.services.setup_status import SETUP_PATH_KEY, compute_setup_status

    AppSettingsStore().set(k="LLM_PROVIDER", v="gemini")
    AppSettingsStore().set(k="GOOGLE_API_KEY", v="test-key")
    store = RepoRegistryStore()
    store.set_app_state(SETUP_PATH_KEY, "production")
    entry = store.upsert_repo(
        name="App",
        repo_url="https://example.com/org/app.git",
        repo_ref="main",
    )
    store.set_active_repo(entry.repo_key)

    status = compute_setup_status()
    crash = next(c for c in status["checks"] if c["id"] == "crashlytics")
    assert crash["required"] is True
    assert crash["ok"] is False
    assert "Manage repos" in (crash["detail"] or "")

    cred = tmp_path / "sa.json"
    cred.write_text('{"type":"service_account"}', encoding="utf-8")
    store.upsert_repo(
        name="App",
        repo_url="https://example.com/org/app.git",
        repo_ref="main",
        firebase_project_id="proj-a",
    )
    store.set_google_application_credentials(entry.repo_key, str(cred))

    status2 = compute_setup_status()
    crash2 = next(c for c in status2["checks"] if c["id"] == "crashlytics")
    assert crash2["ok"] is True
    assert crash2["has_credentials"] is True
    assert crash2["has_bq_project"] is True
