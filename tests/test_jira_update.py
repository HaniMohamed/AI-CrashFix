from __future__ import annotations

import json

import pytest

from app.graph.nodes.jira_update import jira_update
from app.services.jira_service import (
    append_mr_block_to_description,
    format_mr_description_block,
    transition_jira_issue,
    update_jira_issue_description,
)


def test_format_mr_description_block_includes_url_and_branch() -> None:
    block = format_mr_description_block(
        pr_url="https://gitlab.example.com/mr/1",
        pr_branch="fix/DE-1-crash",
    )
    assert "h3. Fixora — Merge Request" in block
    assert "https://gitlab.example.com/mr/1" in block
    assert "fix/DE-1-crash" in block
    assert block.startswith("----")


def test_append_mr_block_skips_when_url_already_present() -> None:
    url = "https://gitlab.example.com/mr/9"
    existing = f"Old body\n\n{url}"
    new_desc, changed = append_mr_block_to_description(
        existing, pr_url=url, pr_branch="b"
    )
    assert changed is False
    assert new_desc == existing


def test_append_mr_block_appends_when_missing() -> None:
    new_desc, changed = append_mr_block_to_description(
        "Original analysis",
        pr_url="https://gitlab.example.com/mr/2",
        pr_branch="fix/x",
    )
    assert changed is True
    assert new_desc.startswith("Original analysis")
    assert "https://gitlab.example.com/mr/2" in new_desc
    assert "Open MR" in new_desc


def test_transition_matches_done_by_name(monkeypatch: pytest.MonkeyPatch) -> None:
    calls: list[tuple[str, str]] = []

    class _Eff:
        server_url = "https://jira.example.com"
        email = None
        verify_ssl = "false"
        auth = "bearer"
        token = "t"
        project_key = "DE"
        issue_type = "Sub-task"
        create_fields_json = ""
        create_mode = "standalone"
        parent_issue_key = None

    monkeypatch.setattr(
        "app.services.jira_service.SettingsResolver.effective_jira",
        lambda self, *, repo_key=None: _Eff(),
    )

    def fake_urlopen(req, timeout=30, context=None):
        method = req.get_method()
        url = req.full_url
        calls.append((method, url))

        class _Resp:
            def __enter__(self):
                return self

            def __exit__(self, *a):
                return False

            def read(self):
                if "/transitions" in url and method == "GET":
                    return json.dumps(
                        {
                            "transitions": [
                                {"id": "41", "name": "In Progress", "to": {"name": "In Progress"}},
                                {"id": "61", "name": "Done", "to": {"name": "Done"}},
                            ]
                        }
                    ).encode()
                if method == "GET" and "/issue/" in url:
                    return json.dumps(
                        {"fields": {"status": {"name": "In Progress"}}}
                    ).encode()
                return b""

        return _Resp()

    monkeypatch.setattr("urllib.request.urlopen", fake_urlopen)

    out = transition_jira_issue("DE-100", "Done", mock=False)
    assert out.get("transitioned") is True
    assert out.get("transition_id") == "61"
    assert any(m == "POST" and "/transitions" in u for m, u in calls)


def test_transition_skips_when_already_done(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(
        "app.services.jira_service.get_jira_issue",
        lambda *a, **k: {"fields": {"status": {"name": "Done"}}},
    )
    out = transition_jira_issue("DE-100", "Done", mock=False)
    assert out.get("skipped") is True
    assert "already" in str(out.get("reason") or "")


def test_transition_skips_when_no_matching_transition(monkeypatch: pytest.MonkeyPatch) -> None:
    class _Eff:
        server_url = "https://jira.example.com"
        email = None
        verify_ssl = "false"
        auth = "bearer"
        token = "t"
        project_key = "DE"
        issue_type = "Bug"
        create_fields_json = ""
        create_mode = "standalone"
        parent_issue_key = None

    monkeypatch.setattr(
        "app.services.jira_service.SettingsResolver.effective_jira",
        lambda self, *, repo_key=None: _Eff(),
    )
    monkeypatch.setattr(
        "app.services.jira_service.get_jira_issue",
        lambda *a, **k: {"fields": {"status": {"name": "TO DO"}}},
    )

    def fake_urlopen(req, timeout=30, context=None):
        class _Resp:
            def __enter__(self):
                return self

            def __exit__(self, *a):
                return False

            def read(self):
                return json.dumps(
                    {"transitions": [{"id": "11", "name": "Start Progress", "to": {"name": "In Progress"}}]}
                ).encode()

        return _Resp()

    monkeypatch.setattr("urllib.request.urlopen", fake_urlopen)
    out = transition_jira_issue("DE-100", "Done", mock=False)
    assert out.get("skipped") is True
    assert out.get("reason") == "no_matching_transition"


def test_jira_update_skips_without_pr_url(monkeypatch: pytest.MonkeyPatch) -> None:
    called = {"get": False}

    def boom(*_a, **_k):
        called["get"] = True
        raise AssertionError("should not call Jira")

    monkeypatch.setattr("app.graph.nodes.jira_update.get_jira_issue", boom)
    state = {
        "jira_issue_id": "DE-1",
        "pr_url": None,
        "skip_jira_creation": False,
    }
    out = jira_update(state)
    assert called["get"] is False
    assert out.get("jira_update_error") is None


def test_jira_update_skips_when_skip_jira(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(
        "app.graph.nodes.jira_update.get_jira_issue",
        lambda *_a, **_k: (_ for _ in ()).throw(AssertionError("no")),
    )
    out = jira_update(
        {
            "skip_jira_creation": True,
            "jira_issue_id": "DE-1",
            "pr_url": "https://example.com/mr/1",
        }
    )
    assert out.get("jira_update_error") is None


def test_jira_update_appends_and_transitions(monkeypatch: pytest.MonkeyPatch) -> None:
    updated: dict = {}
    transitioned: dict = {}

    monkeypatch.setattr(
        "app.graph.nodes.jira_update.get_jira_issue",
        lambda *a, **k: {
            "fields": {
                "description": "Crash analysis body",
                "status": {"name": "In Progress"},
            }
        },
    )

    def fake_update(key, description, *, mock=False, repo_key=None):
        updated["key"] = key
        updated["description"] = description
        return {"updated": True}

    def fake_transition(key, name="Done", *, mock=False, repo_key=None):
        transitioned["key"] = key
        transitioned["name"] = name
        return {"transitioned": True}

    monkeypatch.setattr("app.graph.nodes.jira_update.update_jira_issue_description", fake_update)
    monkeypatch.setattr("app.graph.nodes.jira_update.transition_jira_issue", fake_transition)

    out = jira_update(
        {
            "jira_issue_id": "DE-55",
            "pr_url": "https://gitlab.example.com/mr/55",
            "pr_branch": "fix/DE-55",
            "skip_jira_creation": False,
            "mock": False,
        }
    )
    assert out.get("jira_update_error") is None
    assert updated["key"] == "DE-55"
    assert "https://gitlab.example.com/mr/55" in updated["description"]
    assert "Crash analysis body" in updated["description"]
    assert transitioned == {"key": "DE-55", "name": "Done"}


def test_jira_update_records_error_without_raising(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(
        "app.graph.nodes.jira_update.get_jira_issue",
        lambda *a, **k: (_ for _ in ()).throw(RuntimeError("boom")),
    )
    out = jira_update(
        {
            "jira_issue_id": "DE-1",
            "pr_url": "https://example.com/mr/1",
            "skip_jira_creation": False,
        }
    )
    assert "boom" in str(out.get("jira_update_error") or "")


def test_update_description_mock() -> None:
    out = update_jira_issue_description("DE-1", "new text", mock=True)
    assert out["updated"] is True
    assert out["description"] == "new text"
