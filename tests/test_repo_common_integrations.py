from __future__ import annotations

from app.services.app_settings_store import AppSettingsStore
from app.services.repo_registry_store import RepoRegistryStore
from app.services.settings_resolver import SettingsResolver


def test_repo_does_not_override_jira_base_or_token(monkeypatch, tmp_path) -> None:
    monkeypatch.setenv("AI_CRASH_FIX_CRASH_STORE_BACKEND", "sqlite")
    monkeypatch.setenv("AI_CRASH_FIX_REPO_REGISTRY_DB", str(tmp_path / "registry.db"))
    monkeypatch.delenv("AI_CRASH_FIX_CRASH_DB_URL", raising=False)

    import app.config as cfg

    monkeypatch.setattr(cfg, "JIRA_SERVER_URL", "https://env-jira.example.com")
    monkeypatch.setattr(cfg, "JIRA_EMAIL", "env@example.com")
    monkeypatch.setattr(cfg, "JIRA_TOKEN", "env-token")
    monkeypatch.setattr(cfg, "GITLAB_TOKEN", "env-gitlab-token")

    AppSettingsStore.clear_shared_for_tests()
    RepoRegistryStore.clear_shared_for_tests()
    app = AppSettingsStore()
    app.set(k="JIRA_SERVER_URL", v="https://settings-jira.example.com")
    app.set(k="JIRA_EMAIL", v="settings@example.com")
    app.set(k="JIRA_TOKEN", v="settings-token")
    app.set(k="GITLAB_TOKEN", v="settings-gitlab-token")

    store = RepoRegistryStore()
    entry = store.upsert_repo(
        name="Repo",
        repo_url="https://example.com/org/repo.git",
        repo_ref="main",
        jira_project_key="APP",
        jira_server_url="https://repo-jira.example.com",
        jira_email="repo@example.com",
        jira_token="repo-token",
    )

    effective = SettingsResolver().effective_jira(repo_key=entry.repo_key)
    assert effective.server_url == "https://settings-jira.example.com"
    assert effective.email == "settings@example.com"
    assert effective.token == "settings-token"

    gl = SettingsResolver().effective_gitlab(repo_key=entry.repo_key)
    assert gl.token == "settings-gitlab-token"

