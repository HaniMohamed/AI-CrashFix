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
