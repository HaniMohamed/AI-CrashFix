from __future__ import annotations

from pathlib import Path
from typing import Any

from app.services.gosi_brain_auth import check_gosi_brain_authorization
from app.services.launch_settings import (
    DEFAULT_LAUNCH_ENV_FILENAME,
    default_launch_env_file_path,
    env_file_nonempty,
)
from app.services.settings_resolver import SettingsResolver


def gosi_brain_launch_health() -> dict[str, Any]:
    """
    Informational GOSI Brain credential status for ``/api/health``.

    Standalone Fixora does **not** hard-gate the UI on CodeFaster / launch-env
    JWT freshness. Configure GOSI Brain (or another LLM) in Settings; runs fail
    with a normal API error if credentials are missing when a run starts.
    """
    env_path = default_launch_env_file_path()
    present = env_path.is_file()
    nonempty = env_file_nonempty(env_path) if present else False

    base: dict[str, Any] = {
        "required": False,
        "provider": None,
        "env_file_path": str(env_path),
        "env_file_present": present,
        "env_file_nonempty": nonempty,
        "authorization_present": False,
        "authorization_expired": False,
        "authorization_expires_at": None,
        "reason": None,
        "ok": True,
    }

    try:
        resolver = SettingsResolver()
        provider = resolver.effective_llm_provider()
    except Exception as exc:
        base["reason"] = "settings_unavailable"
        base["detail"] = str(exc)
        return base

    base["provider"] = provider
    if provider != "gosi-brain":
        return base

    try:
        auth = (resolver.effective_gosi_brain().get("authorization") or "").strip() or None
    except Exception:
        auth = None

    status = check_gosi_brain_authorization(auth)
    base["authorization_present"] = status.present
    base["authorization_expired"] = status.expired
    base["authorization_expires_at"] = status.expires_at
    if not status.present:
        base["reason"] = "authorization_missing"
    elif status.expired:
        base["reason"] = "authorization_expired"
    return base


def default_launch_env_display_path() -> str:
    return f"~/{DEFAULT_LAUNCH_ENV_FILENAME}"
