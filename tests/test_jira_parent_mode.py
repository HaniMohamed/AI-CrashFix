from __future__ import annotations

from pathlib import Path

import pytest

from app.services.jira_service import _build_issue_fields, create_jira_issue
from app.services.repo_registry_store import (
    RepoRegistryStore,
    normalize_jira_create_mode,
)
from app.services.sqlite_util import reset_schema_cache_for_tests


def test_normalize_jira_create_mode() -> None:
    assert normalize_jira_create_mode(None) == "standalone"
    assert normalize_jira_create_mode("") == "standalone"
    assert normalize_jira_create_mode("standalone") == "standalone"
    assert normalize_jira_create_mode("under_parent") == "under_parent"
    assert normalize_jira_create_mode("sub_issue") == "under_parent"


def test_build_issue_fields_includes_parent_when_set() -> None:
    fields = _build_issue_fields(
        project="DE",
        summary="Crash",
        description="d",
        issue_type="Sub-task",
        extra_fields={},
        parent_issue_key="de-12345",
    )
    assert fields["parent"] == {"key": "DE-12345"}
    assert fields["issuetype"] == {"name": "Sub-task"}


def test_build_issue_fields_omits_parent_when_empty() -> None:
    fields = _build_issue_fields(
        project="DE",
        summary="Crash",
        description="d",
        issue_type="Bug",
        extra_fields={},
        parent_issue_key=None,
    )
    assert "parent" not in fields


def test_persist_jira_create_mode_and_parent(tmp_path: Path) -> None:
    reset_schema_cache_for_tests()
    store = RepoRegistryStore(db_path=str(tmp_path / "repo_registry.db"))
    entry = store.upsert_repo(
        name="gosi",
        repo_url="https://gitlab.example.com/super-app/gosi-super-app.git",
        repo_ref="uat",
        jira_create_mode="under_parent",
        jira_parent_issue_key="de-999",
        jira_issue_type="Sub-task",
    )
    assert entry.jira_create_mode == "under_parent"
    assert entry.jira_parent_issue_key == "DE-999"
    reloaded = store.get_repo(entry.repo_key)
    assert reloaded is not None
    assert reloaded.jira_create_mode == "under_parent"
    assert reloaded.jira_parent_issue_key == "DE-999"


def test_under_parent_without_key_raises(monkeypatch: pytest.MonkeyPatch) -> None:
    class _Eff:
        server_url = "https://jira.example.com"
        email = None
        verify_ssl = "false"
        auth = "bearer"
        token = "t"
        project_key = "DE"
        issue_type = "Sub-task"
        create_fields_json = None
        create_mode = "under_parent"
        parent_issue_key = None

    monkeypatch.setattr(
        "app.services.jira_service.SettingsResolver.effective_jira",
        lambda self, *, repo_key=None: _Eff(),
    )
    with pytest.raises(RuntimeError, match="parent issue key"):
        create_jira_issue("s", "d", "DE", "Sub-task", repo_key="rk")
