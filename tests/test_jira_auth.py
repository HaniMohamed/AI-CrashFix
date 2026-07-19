from __future__ import annotations

from app.services.jira_service import (
    _build_issue_fields,
    _jira_auth_header,
    _parse_create_fields,
    _summarize_jira_error_body,
    _use_basic_auth,
)
from app.services.settings_resolver import EffectiveJiraConfig


def _eff(**kwargs) -> EffectiveJiraConfig:
    base = dict(
        server_url="https://jira.gosi.ins",
        email="user@example.com",
        verify_ssl="false",
        auth="auto",
        token="pat-token",
        project_key="DE",
        issue_type="Bug",
        create_fields_json=None,
        create_mode="standalone",
        parent_issue_key=None,
    )
    base.update(kwargs)
    return EffectiveJiraConfig(**base)


def test_auto_uses_bearer_for_server_dc_even_with_email() -> None:
    assert _use_basic_auth(_eff()) is False
    assert _jira_auth_header(_eff()) == "Bearer pat-token"


def test_auto_uses_basic_for_cloud_with_email() -> None:
    eff = _eff(server_url="https://acme.atlassian.net", auth="auto")
    assert _use_basic_auth(eff) is True
    assert _jira_auth_header(eff).startswith("Basic ")


def test_force_bearer() -> None:
    eff = _eff(server_url="https://acme.atlassian.net", auth="bearer")
    assert _use_basic_auth(eff) is False


def test_force_basic_on_prem() -> None:
    eff = _eff(auth="basic")
    assert _use_basic_auth(eff) is True


def test_summarize_html_401() -> None:
    body = '<html><p>Basic Authentication Failure - Reason : AUTHENTICATED_FAILED</p></html>'
    assert "AUTHENTICATED_FAILED" in _summarize_jira_error_body(body)


def test_parse_create_fields_concerned_de_team() -> None:
    fields = _parse_create_fields(
        '{"customfield_11404":{"value":"Individual App + Taqdeer"}}'
    )
    assert fields["customfield_11404"] == {"value": "Individual App + Taqdeer"}
    built = _build_issue_fields(
        project="DE",
        summary="s",
        description="d",
        issue_type="Bug",
        extra_fields=fields,
    )
    assert built["customfield_11404"]["value"] == "Individual App + Taqdeer"
    assert built["project"]["key"] == "DE"


def test_sanitize_summary_strips_newlines() -> None:
    from app.services.jira_service import _sanitize_jira_summary

    assert (
        _sanitize_jira_summary("Crash\nin\r\noffer\nstep")
        == "Crash in offer step"
    )
    built = _build_issue_fields(
        project="DE",
        summary="Line1\nLine2",
        description="d",
        issue_type="Bug",
        extra_fields={},
    )
    assert "\n" not in built["summary"]
    assert built["summary"] == "Line1 Line2"
