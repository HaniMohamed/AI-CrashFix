"""Live connectivity probes for setup wizard / settings test buttons."""

from __future__ import annotations

import json
import os
import ssl
import urllib.error
import urllib.parse
import urllib.request
from typing import Any

from app.services.settings_resolver import EffectiveGitlabConfig, EffectiveJiraConfig, SettingsResolver


def _pick_secret(override: str | None, saved: str | None) -> str | None:
    text = (override or "").strip()
    if text:
        return text
    saved_text = (saved or "").strip()
    return saved_text or None


def _pick_str(override: str | None, saved: str | None) -> str | None:
    text = (override or "").strip()
    if text:
        return text
    saved_text = (saved or "").strip()
    return saved_text or None


def check_store_connection(
    *,
    backend: str,
    db_url: str | None = None,
    username: str | None = None,
    password: str | None = None,
    user_id: str | None = None,
) -> dict[str, Any]:
    """Verify crash-store connectivity without persisting configuration."""
    from app.services.store_bootstrap import compose_db_url, load_store_bootstrap, test_postgres_store

    backend_norm = (backend or "").strip().lower()
    if backend_norm not in {"sqlite", "postgres"}:
        raise ValueError("backend must be 'sqlite' or 'postgres'")

    if backend_norm == "sqlite":
        return {
            "ok": True,
            "message": "Local SQLite — no remote connection required.",
        }

    raw_url = (db_url or "").strip()
    if not raw_url and (username or password):
        raise ValueError("db_url is required (host/database); username/password are optional extras")
    if not raw_url:
        existing = load_store_bootstrap() or {}
        raw_url = (existing.get("db_url") or os.getenv("AI_CRASH_FIX_CRASH_DB_URL") or "").strip()
    if not raw_url:
        raise ValueError("db_url is required for postgres")

    composed_url = compose_db_url(raw_url, username=username, password=password)
    uid = (user_id or "").strip()
    if not uid:
        raise ValueError("user_id is required for postgres")

    ok, error = test_postgres_store(db_url=composed_url, user_id=uid)
    if not ok:
        raise ValueError(error or "Postgres connection failed")
    return {"ok": True, "message": "Postgres connection successful."}


def check_jira_connection(
    *,
    server_url: str | None = None,
    email: str | None = None,
    token: str | None = None,
    auth: str | None = None,
    verify_ssl: str | None = None,
) -> dict[str, Any]:
    """Verify Jira REST credentials via GET /rest/api/2/myself."""
    from app.services.jira_service import _jira_request

    saved = SettingsResolver().effective_jira()
    eff = EffectiveJiraConfig(
        server_url=_pick_str(server_url, saved.server_url),
        email=_pick_str(email, saved.email),
        verify_ssl=_pick_str(verify_ssl, saved.verify_ssl),
        auth=_pick_str(auth, saved.auth),
        token=_pick_secret(token, saved.token),
        project_key=saved.project_key,
        issue_type=saved.issue_type,
        create_fields_json=saved.create_fields_json,
        create_mode=saved.create_mode,
        parent_issue_key=saved.parent_issue_key,
    )
    if not (eff.server_url or "").strip():
        raise ValueError("Jira server URL is required")
    if not (eff.token or "").strip():
        raise ValueError("Jira token is required")

    result = _jira_request(eff, "GET", "/rest/api/2/myself") or {}
    display = (result.get("displayName") or result.get("name") or "").strip()
    account = (result.get("emailAddress") or result.get("key") or "").strip()
    detail = display or account or "authenticated"
    return {"ok": True, "message": f"Connected to Jira as {detail}."}


def _gitlab_api_base(server_url: str) -> str:
    base = (server_url or "").strip().rstrip("/")
    if not base:
        raise ValueError("GitLab server URL is required")
    if base.endswith("/api/v4"):
        return base
    return f"{base}/api/v4"


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


def _gitlab_ssl_context(*, verify_ssl: str | None, ca_bundle: str | None) -> ssl.SSLContext | None:
    verify = _parse_bool(verify_ssl, default=True)
    bundle = (ca_bundle or "").strip() or None
    if verify:
        if bundle:
            return ssl.create_default_context(cafile=bundle)
        return None
    return ssl._create_unverified_context()  # noqa: SLF001


def check_gitlab_connection(
    *,
    server_url: str | None = None,
    token: str | None = None,
    verify_ssl: str | None = None,
    ca_bundle: str | None = None,
) -> dict[str, Any]:
    """Verify GitLab REST credentials via GET /api/v4/user."""
    saved = SettingsResolver().effective_gitlab()
    eff = EffectiveGitlabConfig(
        server_url=_pick_str(server_url, saved.server_url),
        verify_ssl=_pick_str(verify_ssl, saved.verify_ssl),
        token=_pick_secret(token, saved.token),
        ca_bundle=_pick_str(ca_bundle, saved.ca_bundle),
        project=saved.project,
    )
    if not (eff.server_url or "").strip():
        raise ValueError("GitLab server URL is required")
    if not (eff.token or "").strip():
        raise ValueError("GitLab token is required")

    base = _gitlab_api_base(eff.server_url or "")
    url = f"{base}/user"
    req = urllib.request.Request(
        url,
        method="GET",
        headers={
            "PRIVATE-TOKEN": eff.token or "",
            "Accept": "application/json",
        },
    )
    try:
        with urllib.request.urlopen(
            req,
            timeout=30,
            context=_gitlab_ssl_context(verify_ssl=eff.verify_ssl, ca_bundle=eff.ca_bundle),
        ) as resp:
            raw = resp.read() or b""
            if not raw.strip():
                return {"ok": True, "message": "Connected to GitLab."}
            try:
                data = json.loads(raw.decode("utf-8"))
            except json.JSONDecodeError:
                return {"ok": True, "message": "Connected to GitLab."}
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", errors="replace") if exc.fp else ""
        raise ValueError(f"GitLab API error ({exc.code}): {body[:400]}") from exc
    except urllib.error.URLError as exc:
        raise ValueError(f"GitLab request failed: {exc}") from exc

    username = (data.get("username") or data.get("name") or "").strip()
    detail = username or "authenticated"
    return {"ok": True, "message": f"Connected to GitLab as {detail}."}


def check_llm_connection(
    *,
    provider: str | None = None,
    gemini_model: str | None = None,
    google_api_key: str | None = None,
    openai_url: str | None = None,
    openai_model: str | None = None,
    openai_api_key: str | None = None,
    gosi_brain_url: str | None = None,
    gosi_brain_model: str | None = None,
    gosi_brain_authorization: str | None = None,
    gosi_brain_api_key: str | None = None,
    gosi_brain_oauth_identity_domain_name: str | None = None,
    gosi_brain_user_id: str | None = None,
    gosi_brain_temperature: float | None = None,
    gosi_brain_streaming: str | None = None,
) -> dict[str, Any]:
    """Verify LLM provider credentials with a minimal probe call."""
    resolver = SettingsResolver()
    name = (provider or resolver.effective_llm_provider() or "gemini").strip().lower()

    if name == "gemini":
        g = resolver.effective_google()
        api_key = _pick_secret(google_api_key, g.get("api_key"))
        model = _pick_str(gemini_model, g.get("model")) or "gemini-2.5-flash"
        if not api_key:
            raise ValueError("Google API key is required")
        from app.services.llm_providers.gemini_provider import GeminiProvider

        reply = GeminiProvider(api_key=api_key, model=model).call(
            "You are a connectivity probe.",
            "Reply with exactly: OK",
        )
        preview = (reply or "").strip()[:80]
        return {"ok": True, "message": f"Gemini responded: {preview or 'OK'}"}

    if name == "openai":
        o = resolver.effective_openai()
        api_key = _pick_secret(openai_api_key, o.get("api_key"))
        base_url = _pick_str(openai_url, o.get("url")) or "https://api.openai.com/v1"
        model = _pick_str(openai_model, o.get("model")) or "gpt-4o-mini"
        if not api_key:
            raise ValueError("OpenAI API key is required")
        from app.services.llm_providers.openai_provider import OpenAIProvider

        reply = OpenAIProvider(api_key=api_key, base_url=base_url, model=model).call(
            "You are a connectivity probe.",
            "Reply with exactly: OK",
        )
        preview = (reply or "").strip()[:80]
        return {"ok": True, "message": f"OpenAI responded: {preview or 'OK'}"}

    if name == "gosi-brain":
        gb = resolver.effective_gosi_brain()
        url = _pick_str(gosi_brain_url, gb.get("url"))
        model = _pick_str(gosi_brain_model, gb.get("model"))
        authorization = _pick_secret(gosi_brain_authorization, gb.get("authorization"))
        api_key = _pick_secret(gosi_brain_api_key, gb.get("api_key"))
        oauth_domain = _pick_str(
            gosi_brain_oauth_identity_domain_name,
            gb.get("oauth_domain"),
        )
        user_id = _pick_str(gosi_brain_user_id, gb.get("user_id"))
        temperature = gosi_brain_temperature
        if temperature is None:
            raw_temp = gb.get("temperature")
            temperature = float(raw_temp) if raw_temp is not None else 0.7
        streaming = _pick_str(gosi_brain_streaming, gb.get("streaming_mode")) or "auto"
        if not url:
            raise ValueError("GOSI Brain URL is required")
        if not authorization:
            raise ValueError("GOSI Brain authorization header is required")
        if not api_key:
            raise ValueError("GOSI Brain API key is required")
        from app.services.llm_providers.gosi_brain_provider import GosiBrainProvider

        provider_obj = GosiBrainProvider(
            url=url,
            model=model,
            authorization=authorization,
            api_key=api_key,
            oauth_domain=oauth_domain,
            user_id=user_id,
            temperature=temperature,
            streaming_mode=streaming,
            connect_timeout=15,
            idle_timeout=30,
            timeout=45,
        )
        reply = provider_obj.call(
            "You are a connectivity probe.",
            "Reply with exactly: OK",
        )
        preview = (reply or "").strip()[:80]
        return {"ok": True, "message": f"GOSI Brain responded: {preview or 'OK'}"}

    raise ValueError(f"Unknown LLM provider: {name!r}")
