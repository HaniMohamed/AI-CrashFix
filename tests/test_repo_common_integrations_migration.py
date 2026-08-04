from __future__ import annotations


def test_cleanup_migration_clears_legacy_repo_jira_base_fields(monkeypatch, tmp_path):
    monkeypatch.setenv("AI_CRASH_FIX_CRASH_STORE_BACKEND", "sqlite")
    monkeypatch.setenv("AI_CRASH_FIX_REPO_REGISTRY_DB", str(tmp_path / "registry.db"))
    monkeypatch.delenv("AI_CRASH_FIX_CRASH_DB_URL", raising=False)

    import app.config as cfg
    import app.services.app_settings_store as app_settings_store
    import app.services.repo_registry_store as repo_registry_store

    monkeypatch.setattr(cfg, "AI_CRASH_FIX_CRASH_STORE_BACKEND", "sqlite")
    monkeypatch.setattr(cfg, "AI_CRASH_FIX_CRASH_DB_URL", None)
    app_settings_store.AppSettingsStore.clear_shared_for_tests()
    repo_registry_store.RepoRegistryStore.clear_shared_for_tests()

    from app.services.repo_common_integrations_migration import (
        migrate_repo_common_integrations_cleanup,
    )
    from app.services.repo_registry_store import RepoRegistryStore

    reg = RepoRegistryStore()
    entry = reg.upsert_repo(
        name="App",
        repo_url="https://example.com/org/app.git",
        repo_ref="main",
        jira_project_key="APP",
        jira_server_url="https://jira.example.com",
        jira_email="me@example.com",
        jira_token="repo-secret-token",
    )
    assert entry.has_jira_token is True
    assert (entry.jira_server_url or "").strip()
    assert (entry.jira_email or "").strip()

    result = migrate_repo_common_integrations_cleanup(force=True)
    assert result["repos_updated"] == 1
    refreshed = reg.get_repo(entry.repo_key)
    assert refreshed is not None
    assert refreshed.has_jira_token is False
    assert refreshed.jira_server_url is None
    assert refreshed.jira_email is None
    assert (refreshed.jira_project_key or "").strip() == "APP"

    again = migrate_repo_common_integrations_cleanup(force=False)
    assert again["skipped"] == 1

