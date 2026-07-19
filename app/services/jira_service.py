from __future__ import annotations

import base64
import json
import re
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


def _is_jira_cloud(server_url: str | None) -> bool:
    return "atlassian.net" in (server_url or "").lower()


def _use_basic_auth(eff: EffectiveJiraConfig) -> bool:
    """
    Choose auth scheme.

    - Cloud API tokens: Basic ``email:api_token``
    - Server / Data Center PATs: ``Bearer <token>`` (Basic with email fails AUTHENTICATED_FAILED)
    """
    mode = (eff.auth or "auto").strip().lower() or "auto"
    email = (eff.email or "").strip()
    if mode in {"basic", "email", "password"}:
        return True
    if mode in {"bearer", "pat", "token"}:
        return False
    # auto
    return bool(email) and _is_jira_cloud(eff.server_url)


def _jira_auth_header(eff: EffectiveJiraConfig) -> str:
    token = (eff.token or "").strip()
    if not token:
        raise RuntimeError("Missing Jira token. Set JIRA_TOKEN or repo Jira token.")
    if _use_basic_auth(eff):
        email = (eff.email or "").strip()
        if not email:
            raise RuntimeError(
                "Jira Basic auth requires JIRA_EMAIL (Cloud API token email, or Server username)."
            )
        raw = f"{email}:{token}".encode("utf-8")
        return "Basic " + base64.b64encode(raw).decode("ascii")
    return f"Bearer {token}"


def _jira_ssl_context(eff: EffectiveJiraConfig) -> ssl.SSLContext | None:
    verify = _parse_bool(eff.verify_ssl, default=True)
    if verify:
        return None
    return ssl._create_unverified_context()  # noqa: SLF001


def _summarize_jira_error_body(body: str) -> str:
    text = (body or "").strip()
    if not text:
        return ""
    # Prefer the explicit auth failure line from Jira's HTML 401 page.
    for pat in (
        r"Basic Authentication Failure[^<]*",
        r"AUTHENTICATED_FAILED",
        r"Unauthorized \(401\)",
    ):
        m = re.search(pat, text, flags=re.IGNORECASE)
        if m:
            return m.group(0).strip()
    if "<html" in text.lower() or "<!doctype" in text.lower():
        stripped = re.sub(r"(?is)<script.*?>.*?</script>", " ", text)
        stripped = re.sub(r"(?is)<style.*?>.*?</style>", " ", stripped)
        stripped = re.sub(r"(?s)<[^>]+>", " ", stripped)
        stripped = re.sub(r"\s+", " ", stripped).strip()
        if stripped:
            return stripped[:400]
    return text[:800]


def _parse_create_fields(raw: str | None) -> dict[str, Any]:
    """Parse ``JIRA_CREATE_FIELDS`` JSON object into issue ``fields`` entries."""
    text = (raw or "").strip()
    if not text:
        return {}
    try:
        parsed = json.loads(text)
    except json.JSONDecodeError as exc:
        raise RuntimeError(f"Invalid JIRA_CREATE_FIELDS JSON: {exc}") from exc
    if not isinstance(parsed, dict):
        raise RuntimeError("JIRA_CREATE_FIELDS must be a JSON object of field_id → value.")
    out: dict[str, Any] = {}
    for key, value in parsed.items():
        fid = str(key).strip()
        if not fid:
            continue
        out[fid] = value
    return out


def _sanitize_jira_summary(summary: str, *, max_len: int = 255) -> str:
    """Jira rejects summaries that contain newline characters; keep a single-line title."""
    text = re.sub(r"\s+", " ", (summary or "").replace("\u00a0", " ")).strip()
    if not text:
        text = "[AI Crash Fix] Crash"
    if len(text) > max_len:
        text = text[: max_len - 1].rstrip() + "…"
    return text


def _build_issue_fields(
    *,
    project: str,
    summary: str,
    description: str,
    issue_type: str,
    extra_fields: dict[str, Any],
    parent_issue_key: str | None = None,
) -> dict[str, Any]:
    fields: dict[str, Any] = {
        "project": {"key": project},
        "summary": _sanitize_jira_summary(summary),
        "description": description,
        "issuetype": {"name": issue_type},
    }
    parent = (parent_issue_key or "").strip().upper()
    if parent:
        fields["parent"] = {"key": parent}
    # Extra/custom fields override only when not colliding with core keys unless explicitly set.
    for key, value in extra_fields.items():
        if key in {"project", "issuetype", "parent"}:
            continue
        if key == "summary" and isinstance(value, str):
            fields[key] = _sanitize_jira_summary(value)
            continue
        fields[key] = value
    return fields


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
    Auth: Cloud uses Basic (email + API token); Server/DC PATs use Bearer (see ``JIRA_AUTH``).
    Extra create fields come from ``JIRA_CREATE_FIELDS`` (required custom fields, etc.).
    When create_mode is ``under_parent``, sets ``parent.key`` from the repo parent story key
    (requires a Sub-task issue type in classic Jira).
    """
    from app.services.repo_registry_store import normalize_jira_create_mode

    eff = SettingsResolver().effective_jira(repo_key=(repo_key or "").strip() or None)
    itype = (issue_type or eff.issue_type or "Bug").strip() or "Bug"
    project = (project_key or eff.project_key or "").strip()
    mode = normalize_jira_create_mode(eff.create_mode)
    parent_key = (eff.parent_issue_key or "").strip().upper() or None

    if mode == "under_parent" and not parent_key:
        raise RuntimeError(
            "Jira create mode is under_parent but no parent issue key is set. "
            "Set Parent story/issue key in Manage Repos."
        )

    if mock:
        return mock_create_jira_issue(
            summary, description, project, itype, parent_issue_key=parent_key if mode == "under_parent" else None
        )

    if not project:
        raise RuntimeError("Missing Jira project key. Set per-repo project key or JIRA_PROJECT_KEY.")

    base_url = _jira_base_url(eff)
    url = f"{base_url}/rest/api/2/issue"
    extra = _parse_create_fields(eff.create_fields_json)
    payload: dict[str, Any] = {
        "fields": _build_issue_fields(
            project=project,
            summary=summary,
            description=description,
            issue_type=itype,
            extra_fields=extra,
            parent_issue_key=parent_key if mode == "under_parent" else None,
        )
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
        detail = _summarize_jira_error_body(body) or body
        hint = ""
        if exc.code == 401 and _use_basic_auth(eff):
            hint = (
                " Hint: for Jira Server/Data Center personal access tokens, set "
                "JIRA_AUTH=bearer (do not use Basic email:token)."
            )
        elif exc.code == 401:
            hint = " Hint: check JIRA_TOKEN (PAT) is valid and not expired."
        elif exc.code == 400 and "customfield_" in detail and not extra:
            hint = (
                " Hint: set JIRA_CREATE_FIELDS JSON for required custom fields "
                '(e.g. Concerned DE Team: {"customfield_11404":{"value":"Individual App + Taqdeer"}}).'
            )
        elif exc.code == 400 and mode == "under_parent" and "not a sub-task" in detail.lower():
            hint = (
                " Hint: classic Jira only allows parent on Sub-task issue types. "
                "Set Issue type to Sub-task (exact name in your project)."
            )
        elif exc.code == 400 and mode == "under_parent" and "parent" in detail.lower():
            hint = (
                " Hint: check Parent story key and that Issue type is Sub-task."
            )
        raise RuntimeError(f"Jira API error ({exc.code}) creating issue: {detail}.{hint}") from exc
    except urllib.error.URLError as exc:
        raise RuntimeError(f"Jira request failed: {exc}") from exc


def mock_create_jira_issue(
    summary: str,
    description: str,
    project_key: str | None,
    issue_type: str,
    *,
    parent_issue_key: str | None = None,
) -> dict[str, Any]:
    project = (project_key or "DE").strip() or "DE"
    key = f"{project}-XXXX"
    out: dict[str, Any] = {
        "id": "000000",
        "key": key,
        "self": f"https://jira.example.com/rest/api/2/issue/{key}",
    }
    parent = (parent_issue_key or "").strip().upper()
    if parent:
        out["fields"] = {"parent": {"key": parent}, "issuetype": {"name": issue_type}}
    return out
