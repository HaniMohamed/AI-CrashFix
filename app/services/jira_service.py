from __future__ import annotations

import json
import ssl
import urllib.error
import urllib.request
from typing import Any

from app.config import JIRA_PROJECT_KEY, JIRA_SERVER_URL, JIRA_TOKEN, JIRA_VERIFY_SSL


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


def _jira_base_url() -> str:
    base = (JIRA_SERVER_URL or "").strip()
    if not base:
        raise RuntimeError("Missing Jira base URL. Set JIRA_SERVER_URL.")
    return base.rstrip("/")


def _jira_auth_header() -> str:
    if not JIRA_TOKEN:
        raise RuntimeError("Missing Jira token. Set JIRA_TOKEN.")
    return f"Bearer {JIRA_TOKEN}"


def _jira_ssl_context() -> ssl.SSLContext | None:
    verify = _parse_bool(JIRA_VERIFY_SSL, default=True)
    if verify:
        return None
    return ssl._create_unverified_context()  # noqa: SLF001


def create_jira_issue(
    summary: str,
    description: str,
    project_key: str | None,
    issue_type: str,
    *,
    mock: bool = False,
) -> dict[str, Any]:
    """
    Create a Jira issue via REST API.

    Uses:
    - JIRA_SERVER_URL + JIRA_TOKEN + JIRA_PROJECT_KEY (from app.config)
    """

    if mock:
        return mock_create_jira_issue(summary, description, project_key, issue_type)

    project = (project_key or JIRA_PROJECT_KEY or "").strip()
    if not project:
        raise RuntimeError("Missing Jira project key. Pass project_key or set JIRA_PROJECT_KEY.")

    base_url = _jira_base_url()
    url = f"{base_url}/rest/api/2/issue"

    payload: dict[str, Any] = {
        "fields": {
            "project": {"key": project},
            "summary": summary,
            "description": description,
            "issuetype": {"name": issue_type},
        }
    }

    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(
        url,
        data=data,
        method="POST",
        headers={
            "Authorization": _jira_auth_header(),
            "Accept": "application/json",
            "Content-Type": "application/json",
        },
    )

    try:
        with urllib.request.urlopen(req, timeout=30, context=_jira_ssl_context()) as resp:
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

def mock_create_jira_issue(summary: str, description: str, project_key: str | None, issue_type: str) -> dict[str, Any]:
    return {
        "id": "DE-XXXX",
        "key": "DE-XXXX",
        "self": "https://jira.example.com/rest/api/2/issue/DE-XXXX",
    }