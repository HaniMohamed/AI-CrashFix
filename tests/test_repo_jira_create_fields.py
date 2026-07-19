from __future__ import annotations

from pathlib import Path

from app.services.repo_registry_store import RepoRegistryStore
from app.services.sqlite_util import reset_schema_cache_for_tests


def test_jira_create_fields_stored_on_repo(tmp_path: Path) -> None:
    reset_schema_cache_for_tests()
    db = tmp_path / "repo_registry.db"
    store = RepoRegistryStore(db_path=str(db))

    payload = '{"customfield_11404":{"value":"Individual App + Taqdeer"}}'
    entry = store.upsert_repo(
        name="gosi-super-app",
        repo_url="https://gitlab.example.com/super-app/gosi-super-app.git",
        repo_ref="uat",
        jira_project_key="DE",
        jira_create_fields=payload,
    )
    assert entry.jira_create_fields == payload

    reloaded = store.get_repo(entry.repo_key)
    assert reloaded is not None
    assert reloaded.jira_create_fields == payload

    listed = store.list_repos()
    assert listed[0].jira_create_fields == payload

    # Empty clears the stored override.
    cleared = store.upsert_repo(
        name="gosi-super-app",
        repo_url="https://gitlab.example.com/super-app/gosi-super-app.git",
        repo_ref="uat",
        jira_project_key="DE",
        jira_create_fields="",
    )
    assert cleared.jira_create_fields is None
