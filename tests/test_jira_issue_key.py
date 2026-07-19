from __future__ import annotations

from app.graph.nodes.jira_create import jira_create


def test_jira_create_stores_key_not_numeric_id(monkeypatch) -> None:
    def fake_create(*_args, **_kwargs):
        return {
            "id": "315292",
            "key": "DE-99999",
            "self": "https://jira.example.com/rest/api/2/issue/315292",
        }

    monkeypatch.setattr(
        "app.graph.nodes.jira_create.create_jira_issue",
        fake_create,
    )

    class _NoopStore:
        def set_pipeline_flags(self, *_a, **_k):
            return None

    monkeypatch.setattr("app.graph.nodes.jira_create.CrashStore", lambda **_k: _NoopStore())

    state = {
        "crash_id": "c1",
        "exception": "Null check",
        "summary": "Null check in offer",
        "description": "desc",
        "jira_project_key": "DE",
        "issue_type": "Bug",
        "mock": False,
        "repo_key": None,
    }
    out = jira_create(state)
    assert out["jira_issue_id"] == "DE-99999"


def test_jira_create_reuses_existing_issue_id(monkeypatch) -> None:
    created = {"called": False}

    def fake_create(*_args, **_kwargs):
        created["called"] = True
        return {"id": "1", "key": "DE-NEW"}

    flags = {}

    class _Store:
        def set_pipeline_flags(self, crash_id, **kwargs):
            flags["crash_id"] = crash_id
            flags.update(kwargs)

    monkeypatch.setattr(
        "app.graph.nodes.jira_create.create_jira_issue",
        fake_create,
    )
    monkeypatch.setattr("app.graph.nodes.jira_create.CrashStore", lambda **_k: _Store())

    state = {
        "crash_id": "c1",
        "jira_issue_id": "DE-11111",
        "exception": "boom",
    }
    out = jira_create(state)
    assert out["jira_issue_id"] == "DE-11111"
    assert created["called"] is False
    assert flags.get("jira_issue_id") == "DE-11111"
    assert flags.get("jira_created") is True
