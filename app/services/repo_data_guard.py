from __future__ import annotations

from typing import Any

from fastapi import HTTPException

SETTINGS_KEY_REPO_DATA_READONLY = "REPO_DATA_READONLY"


def parse_bool_setting(value: Any) -> bool:
    if value is True:
        return True
    if value is False or value is None:
        return False
    if isinstance(value, (int, float)) and not isinstance(value, bool):
        return bool(value)
    s = str(value).strip().lower()
    if s in ("1", "true", "yes", "on"):
        return True
    if s in ("0", "false", "no", "off", ""):
        return False
    return False


def is_repo_data_readonly() -> bool:
    """When true, repo registry / settings / secrets / index metadata cannot be mutated."""
    try:
        from app.services.app_settings_store import AppSettingsStore

        v = AppSettingsStore().get(k=SETTINGS_KEY_REPO_DATA_READONLY)
        return parse_bool_setting(v)
    except Exception:
        return False


def ensure_repo_data_writable() -> None:
    if is_repo_data_readonly():
        raise HTTPException(
            status_code=403,
            detail=(
                "Repo data is read-only (REPO_DATA_READONLY in app settings). "
                "Cannot modify repos, settings, secrets, or index metadata."
            ),
        )
