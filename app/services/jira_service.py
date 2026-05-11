from __future__ import annotations

import base64
import json
import ssl
import urllib.error
import urllib.request
from typing import Any

from app.services.settings_resolver import EffectiveJiraConfig, SettingsResolver


def _parse_bool(value: Any, default: bool = True) -> bool:
    if value is None:
        return default
    if isinstance(value, bool):
        return value
    text = str(value).strip().lower()
    if text in {"1", "true", "yes", "y", "on"}:
        return True
    if text in {"0", "false", "no", "n", "off"}:
        return False
    return default


def _jira_base_url(eff: EffectiveJiraConfig) -> str:
    base = (eff.server_url or "").strip()
    if not base:
        raise RuntimeError("Missing Jira base URL. Set JIRA_SERVER_URL or repo Jira server URL.")
    return base.rstrip("/")


def _jira_auth_header(eff: EffectiveJiraConfig) -> str:
    token = (eff.token or "").strip()
    if not token:
        raise RuntimeError("Missing Jira token. Set JIRA_TOKEN or repo Jira token.")
    email = (eff.email or "").strip()
    if email:
        raw = f"{email}:{token}".encode("utf-8")
        return "Basic " + base64.b64encode(raw).decode("ascii")
    return f"Bearer {token}"


def _jira_ssl_context(eff: EffectiveJiraConfig) -> ssl.SSLContext | None:
    verify = _parse_bool(eff.verify_ssl, default=True)
    if verify:
        return None
    return ssl._create_unverified_context()  # noqa: SLF001


def create_jira_issue(
    summary: str,
    description: str,
    project_key: str | None,
    issue_type: str | None,
    *,
    mock: bool = False,
    repo_key: str | None = None,
) -> dict[str, Any]:
    """
    Create a Jira issue via REST API.

    Connection settings are resolved for ``repo_key`` (repo row → app settings → .env).
    Jira Cloud / Server API tokens typically use Basic auth (email + token); otherwise Bearer.
    """
    eff = SettingsResolver().effective_jira(repo_key=(repo_key or "").strip() or None)
    itype = (issue_type or eff.issue_type or "Bug").strip() or "Bug"
    project = (project_key or eff.project_key or "").strip()

    if mock:
        return mock_create_jira_issue(summary, description, project, itype)

    if not project:
        raise RuntimeError("Missing Jira project key. Set per-repo project key or JIRA_PROJECT_KEY.")

    base_url = _jira_base_url(eff)
    url = f"{base_url}/rest/api/2/issue"

    payload: dict[str, Any] = {
        "fields": {
            "project": {"key": project},
            "summary": summary,
            "description": description,
            "issuetype": {"name": itype},
        }
    }

    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(
        url,
        data=data,
        method="POST",
        headers={
            "Authorization": _jira_auth_header(eff),
            "Accept": "application/json",
            "Content-Type": "application/json",
        },
    )

    try:
        with urllib.request.urlopen(req, timeout=30, context=_jira_ssl_context(eff)) as resp:
            raw = resp.read() or b"{}"
            try:
                return json.loads(raw.decode("utf-8"))
            except json.JSONDecodeError:
                return {"raw_response": raw.decode("utf-8", errors="replace")}
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", errors="replace") if exc.fp else ""
        raise RuntimeError(f"Jira API error ({exc.code}) creating issue: {body}") from exc
    except urllib.error.URLError as exc:
        raise RuntimeError(f"Jira request failed: {exc}") from exc


def mock_create_jira_issue(
    summary: str, description: str, project_key: str | None, issue_type: str
) -> dict[str, Any]:
    return {
        "id": "DE-XXXX",
        "key": "DE-XXXX",
        "self": "https://jira.example.com/rest/api/2/issue/DE-XXXX",
    }
