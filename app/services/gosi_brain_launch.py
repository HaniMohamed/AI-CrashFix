from __future__ import annotations

from pathlib import Path
from typing import Any

from app.services.gosi_brain_auth import check_gosi_brain_authorization
from app.services.launch_settings import (
    DEFAULT_LAUNCH_ENV_FILENAME,
    default_launch_env_file_path,
    env_file_nonempty,
    parse_env_file,
)
from app.services.settings_resolver import SettingsResolver


def gosi_brain_launch_health() -> dict[str, Any]:
    """
    Launch-time gate for macOS standalone vs CodeFaster host.

    When LLM provider is gosi-brain, require a non-empty
    ``~/crash_fix_gosi_brain_conf.env`` with a present, non-expired
    ``GOSI_BRAIN_AUTHORIZATION`` JWT.

    Never raises — settings/store outages must not 500 ``/api/health``.
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
        base["ok"] = True
        base["reason"] = "settings_unavailable"
        base["detail"] = str(exc)
        return base

    base["provider"] = provider
    base["required"] = provider == "gosi-brain"

    if provider != "gosi-brain":
        return base

    if not present or not nonempty:
        base["ok"] = False
        base["reason"] = "env_file_missing"
        return base

    env_vars = parse_env_file(env_path)
    auth = env_vars.get("GOSI_BRAIN_AUTHORIZATION")
    status = check_gosi_brain_authorization(auth)
    base["authorization_present"] = status.present
    base["authorization_expired"] = status.expired
    base["authorization_expires_at"] = status.expires_at

    if not status.present:
        base["ok"] = False
        base["reason"] = "authorization_missing"
        return base
    if status.expired:
        base["ok"] = False
        base["reason"] = "authorization_expired"
        return base

    base["ok"] = True
    return base


def default_launch_env_display_path() -> str:
    return f"~/{DEFAULT_LAUNCH_ENV_FILENAME}"
