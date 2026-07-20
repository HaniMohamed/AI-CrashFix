from __future__ import annotations

import os


def normalize_user_id(raw: str | None) -> str | None:
    """Strip whitespace and lowercase; empty becomes None."""
    if raw is None:
        return None
    s = str(raw).strip().lower()
    return s or None


def ai_crash_fix_user_id_raw() -> str | None:
    """
    Explicit ``AI_CRASH_FIX_USER_ID`` if set (process env or config).

    When this is present it is the single identity for the app store and for
    GOSI Brain ``custom_session.user_id`` — ``GOSI_BRAIN_USER_ID`` is ignored.
    """
    from app import config as cfg

    raw = (os.getenv("AI_CRASH_FIX_USER_ID") or "").strip() or None
    if not raw:
        raw = (getattr(cfg, "AI_CRASH_FIX_USER_ID", None) or "").strip() or None
    return raw or None


_POSTGRES_USER_ID_MSG = (
    "AI_CRASH_FIX_USER_ID is required when AI_CRASH_FIX_CRASH_STORE_BACKEND=postgres. "
    "Set it in .env or your launch env file (and GOSI_BRAIN_USER_ID if you rely on that fallback)."
)


def resolve_user_id(*, required: bool = False) -> str | None:
    """
    Resolve the current app user id (always normalized lowercase).

    Priority:
    1) ``AI_CRASH_FIX_USER_ID`` (env / config) — if set, GOSI_BRAIN_USER_ID is ignored
    2) ``GOSI_BRAIN_USER_ID`` from config (legacy fallback only)
    """
    from app import config as cfg

    raw = ai_crash_fix_user_id_raw()
    if not raw:
        raw = cfg.GOSI_BRAIN_USER_ID
    user_id = normalize_user_id(raw)
    if required and not user_id:
        raise ValueError(_POSTGRES_USER_ID_MSG)
    return user_id


def assert_postgres_user_id_configured() -> None:
    """Raise ValueError when postgres backend is on but no user id is configured."""
    from app.services.crash_store import uses_postgres_crash_store

    if uses_postgres_crash_store() and not resolve_user_id(required=False):
        raise ValueError(_POSTGRES_USER_ID_MSG)
