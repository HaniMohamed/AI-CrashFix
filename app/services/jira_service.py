from __future__ import annotations

import base64
import json
import logging
import re
import shlex
import ssl
import sys
import urllib.error
import urllib.request
from typing import Any

from app.services.settings_resolver import EffectiveJiraConfig, SettingsResolver

log = logging.getLogger(__name__)
log.setLevel(logging.INFO)
if not any(getattr(h, "_fixora_jira_console", False) for h in log.handlers):
    # Debug-terminal visibility doesn't depend on root logging config (e.g. python
    # debugger / plain `uvicorn` runs without our backend_logging StreamHandler).
    _console_handler = logging.StreamHandler(sys.stdout)
    _console_handler.setFormatter(logging.Formatter("%(asctime)s %(levelname)s [%(name)s] %(message)s"))
    _console_handler._fixora_jira_console = True  # type: ignore[attr-defined]
    log.addHandler(_console_handler)


def _log_curl(
    method: str,
    url: str,
    headers: dict[str, str],
    data: bytes | None,
    *,
    insecure: bool = False,
) -> None:
    """Log an equivalent curl command for a Jira request (auth header redacted)."""
    parts = ["curl", "-X", method.upper()]
    if insecure:
        parts.append("-k")
    for key, value in headers.items():
        shown = "***REDACTED***" if key.lower() == "authorization" else value
        parts += ["-H", shlex.quote(f"{key}: {shown}")]
    if data is not None:
        parts += ["-d", shlex.quote(data.decode("utf-8", errors="replace"))]
    parts.append(shlex.quote(url))
    log.info("Jira request curl: %s", " ".join(parts))


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
        text = "[Fixora] Crash"
    if len(text) > max_len:
        text = text[: max_len - 1].rstrip() + "…"
    return text


def _resolve_issue_type(issue_type: str | None, *, under_parent: bool) -> str:
    """
    Classic Jira only accepts ``fields.parent`` for Sub-task types.

    Normalize common aliases (``Sub-Task``, ``Subtask``) to the canonical ``Sub-task``
    name used by Jira Server/DC. When under a parent, replace Bug/Story/etc. with Sub-task.
    """
    raw = (issue_type or "").strip()
    if not under_parent:
        return raw or "Bug"

    compact = re.sub(r"[\s_-]+", "", raw.lower())
    if compact in {"subtask", "subtasks"}:
        return "Sub-task"
    if compact in {"bug", "story", "task", "improvement", "newfeature", "subbug", ""}:
        return "Sub-task"
    # Custom sub-task-like types (e.g. "EA Review") — keep as configured.
    return raw or "Sub-task"


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
    Extra create fields come from ``JIRA_CREATE_FIELDS`` (required custom fields, etc.)
    for standalone issues only — Sub-task creates skip them (screens often omit those fields).
    When create_mode is ``under_parent``, sets ``parent.key`` and uses issue type ``Sub-task``
    (aliases like ``Sub-Task`` are normalized).
    """
    from app.services.repo_registry_store import normalize_jira_create_mode

    eff = SettingsResolver().effective_jira(repo_key=(repo_key or "").strip() or None)
    mode = normalize_jira_create_mode(eff.create_mode)
    under_parent = mode == "under_parent"
    itype = _resolve_issue_type(issue_type or eff.issue_type, under_parent=under_parent)
    project = (project_key or eff.project_key or "").strip()
    parent_key = (eff.parent_issue_key or "").strip().upper() or None

    if under_parent and not parent_key:
        raise RuntimeError(
            "Jira create mode is under_parent but no parent issue key is set. "
            "Set Parent story/issue key in Manage Repos."
        )

    if mock:
        return mock_create_jira_issue(
            summary,
            description,
            project,
            itype,
            parent_issue_key=parent_key if under_parent else None,
        )

    if not project:
        raise RuntimeError("Missing Jira project key. Set per-repo project key or JIRA_PROJECT_KEY.")

    base_url = _jira_base_url(eff)
    url = f"{base_url}/rest/api/2/issue"
    # Sub-task screens typically do not include Bug-only fields like Concerned DE Team.
    extra = {} if under_parent else _parse_create_fields(eff.create_fields_json)
    payload: dict[str, Any] = {
        "fields": _build_issue_fields(
            project=project,
            summary=summary,
            description=description,
            issue_type=itype,
            extra_fields=extra,
            parent_issue_key=parent_key if under_parent else None,
        )
    }

    data = json.dumps(payload).encode("utf-8")
    headers = {
        "Authorization": _jira_auth_header(eff),
        "Accept": "application/json",
        "Content-Type": "application/json",
    }
    _log_curl("POST", url, headers, data, insecure=not _parse_bool(eff.verify_ssl, default=True))
    req = urllib.request.Request(url, data=data, method="POST", headers=headers)

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
        elif exc.code == 400 and under_parent and "not a sub-task" in detail.lower():
            hint = (
                f" Hint: sent issuetype={itype!r} with parent={parent_key!r}. "
                "Jira requires the canonical name Sub-task (id 10003). "
                "Restart the backend after updating Manage Repos."
            )
        elif exc.code == 400 and under_parent and "parent" in detail.lower():
            hint = (
                f" Hint: check Parent story key ({parent_key}) and Issue type "
                f"(using {itype!r}; must be Sub-task)."
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


def _resolve_eff(*, repo_key: str | None = None) -> EffectiveJiraConfig:
    return SettingsResolver().effective_jira(repo_key=(repo_key or "").strip() or None)


def _jira_request(
    eff: EffectiveJiraConfig,
    method: str,
    path: str,
    *,
    payload: dict[str, Any] | None = None,
) -> dict[str, Any] | None:
    """Perform a Jira REST call. Returns parsed JSON or None for empty bodies."""
    base_url = _jira_base_url(eff)
    url = f"{base_url}{path}"
    data = json.dumps(payload).encode("utf-8") if payload is not None else None
    headers = {
        "Authorization": _jira_auth_header(eff),
        "Accept": "application/json",
    }
    if data is not None:
        headers["Content-Type"] = "application/json"
    _log_curl(method, url, headers, data, insecure=not _parse_bool(eff.verify_ssl, default=True))
    req = urllib.request.Request(url, data=data, method=method.upper(), headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=30, context=_jira_ssl_context(eff)) as resp:
            raw = resp.read() or b""
            if not raw.strip():
                return None
            try:
                return json.loads(raw.decode("utf-8"))
            except json.JSONDecodeError:
                return {"raw_response": raw.decode("utf-8", errors="replace")}
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", errors="replace") if exc.fp else ""
        detail = _summarize_jira_error_body(body) or body
        raise RuntimeError(f"Jira API error ({exc.code}) {method.upper()} {path}: {detail}") from exc
    except urllib.error.URLError as exc:
        raise RuntimeError(f"Jira request failed: {exc}") from exc


def get_jira_issue(
    issue_key: str,
    *,
    fields: str = "description,status",
    mock: bool = False,
    repo_key: str | None = None,
) -> dict[str, Any]:
    """Fetch a Jira issue (default: description + status)."""
    key = (issue_key or "").strip().upper()
    if not key:
        raise RuntimeError("Missing Jira issue key.")
    if mock:
        return {
            "key": key,
            "fields": {
                "description": "Mock description",
                "status": {"name": "In Progress", "id": "3"},
            },
        }
    eff = _resolve_eff(repo_key=repo_key)
    field_q = urllib.request.quote(fields, safe=",")
    result = _jira_request(eff, "GET", f"/rest/api/2/issue/{urllib.request.quote(key, safe='')}?fields={field_q}")
    return result or {}


def update_jira_issue_description(
    issue_key: str,
    description: str,
    *,
    mock: bool = False,
    repo_key: str | None = None,
) -> dict[str, Any]:
    """Replace the issue description via PUT /rest/api/2/issue/{key}."""
    key = (issue_key or "").strip().upper()
    if not key:
        raise RuntimeError("Missing Jira issue key.")
    if mock:
        return {"key": key, "updated": True, "description": description}
    eff = _resolve_eff(repo_key=repo_key)
    _jira_request(
        eff,
        "PUT",
        f"/rest/api/2/issue/{urllib.request.quote(key, safe='')}",
        payload={"fields": {"description": description}},
    )
    return {"key": key, "updated": True}


def transition_jira_issue(
    issue_key: str,
    transition_name: str = "Done",
    *,
    mock: bool = False,
    repo_key: str | None = None,
) -> dict[str, Any]:
    """
    Transition an issue by transition **name** (case-insensitive).

    Looks up available transitions via GET .../transitions, then POSTs the match.
    Returns ``{"skipped": True, "reason": ...}`` when already in the target status
    or when no matching transition exists (does not raise).
    """
    key = (issue_key or "").strip().upper()
    wanted = (transition_name or "").strip()
    if not key:
        raise RuntimeError("Missing Jira issue key.")
    if not wanted:
        raise RuntimeError("Missing Jira transition name.")

    if mock:
        return {"key": key, "transitioned": True, "transition": wanted, "mock": True}

    eff = _resolve_eff(repo_key=repo_key)
    encoded = urllib.request.quote(key, safe="")

    # Skip if already in the target status (status name often matches transition name).
    try:
        issue = get_jira_issue(key, fields="status", mock=False, repo_key=repo_key)
        status_name = (
            ((issue.get("fields") or {}).get("status") or {}).get("name") or ""
        ).strip()
        if status_name.lower() == wanted.lower():
            return {"key": key, "skipped": True, "reason": f"already_{status_name}"}
    except Exception:
        # Transition lookup below is authoritative; ignore status prefetch failures.
        pass

    listed = _jira_request(eff, "GET", f"/rest/api/2/issue/{encoded}/transitions") or {}
    transitions = listed.get("transitions") if isinstance(listed, dict) else None
    if not isinstance(transitions, list):
        transitions = []

    match: dict[str, Any] | None = None
    for t in transitions:
        if not isinstance(t, dict):
            continue
        name = str(t.get("name") or "").strip()
        if name.lower() == wanted.lower():
            match = t
            break
        # Some workflows name the transition after the target status to-status.
        to_name = str(((t.get("to") or {}) if isinstance(t.get("to"), dict) else {}).get("name") or "").strip()
        if to_name.lower() == wanted.lower():
            match = t
            break

    if not match:
        return {
            "key": key,
            "skipped": True,
            "reason": "no_matching_transition",
            "wanted": wanted,
            "available": [str(t.get("name") or "") for t in transitions if isinstance(t, dict)],
        }

    tid = str(match.get("id") or "").strip()
    if not tid:
        return {"key": key, "skipped": True, "reason": "missing_transition_id"}

    _jira_request(
        eff,
        "POST",
        f"/rest/api/2/issue/{encoded}/transitions",
        payload={"transition": {"id": tid}},
    )
    return {
        "key": key,
        "transitioned": True,
        "transition": str(match.get("name") or wanted),
        "transition_id": tid,
    }


def add_comment(
    issue_key: str,
    comment_body: str,
    *,
    mock: bool = False,
    repo_key: str | None = None,
) -> dict[str, Any]:
    """Post a comment via POST /rest/api/2/issue/{key}/comment."""
    key = (issue_key or "").strip().upper()
    if not key:
        raise RuntimeError("Missing Jira issue key.")
    body = (comment_body or "").strip()
    if not body:
        raise RuntimeError("Missing comment body.")
    if mock:
        return {"key": key, "commented": True, "body": body, "mock": True}
    eff = _resolve_eff(repo_key=repo_key)
    result = _jira_request(
        eff,
        "POST",
        f"/rest/api/2/issue/{urllib.request.quote(key, safe='')}/comment",
        payload={"body": body},
    )
    return {"key": key, "commented": True, "response": result or {}}


def format_mr_description_block(*, pr_url: str, pr_branch: str | None = None) -> str:
    """Wiki-markup block appended to a Jira description after MR creation."""
    url = (pr_url or "").strip()
    branch = (pr_branch or "").strip()
    lines = [
        "----",
        "h3. Fixora — Merge Request",
        f"*MR:* [Open MR|{url}]" if url else "*MR:* (missing)",
    ]
    if branch:
        lines.append(f"*Branch:* `{branch}`")
    return "\n".join(lines)


def append_mr_block_to_description(
    description: str | None,
    *,
    pr_url: str,
    pr_branch: str | None = None,
) -> tuple[str, bool]:
    """
    Append the MR block to ``description`` unless ``pr_url`` is already present.

    Returns ``(new_description, changed)``.
    """
    url = (pr_url or "").strip()
    current = description if isinstance(description, str) else ("" if description is None else str(description))
    if url and url in current:
        return current, False
    block = format_mr_description_block(pr_url=url, pr_branch=pr_branch)
    if current.strip():
        return current.rstrip() + "\n\n" + block, True
    return block, True
