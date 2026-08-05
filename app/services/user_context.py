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

    Used for app-store / Postgres row scoping. Independent of
    ``GOSI_BRAIN_USER_ID`` (LLM ``custom_session.user_id``).
    """
    from app import config as cfg

    raw = (os.getenv("AI_CRASH_FIX_USER_ID") or "").strip() or None
    if not raw:
        raw = (getattr(cfg, "AI_CRASH_FIX_USER_ID", None) or "").strip() or None
    return raw or None


_POSTGRES_USER_ID_MSG = (
    "AI_CRASH_FIX_USER_ID is required when AI_CRASH_FIX_CRASH_STORE_BACKEND=postgres. "
    "Set it in .env, the database setup step, or your launch env file."
)


def resolve_user_id(*, required: bool = False) -> str | None:
    """
    Resolve the current app user id (always normalized lowercase).

    Priority:
    1) Authenticated session ``tenant_user_id`` (login account)
    2) ``AI_CRASH_FIX_USER_ID`` (env / config)
    """
    from app.services.auth_context import get_current_session

    session = get_current_session()
    if session is not None:
        return session.user.tenant_user_id

    user_id = normalize_user_id(ai_crash_fix_user_id_raw())
    if required and not user_id:
        raise ValueError(_POSTGRES_USER_ID_MSG)
    return user_id


def assert_postgres_user_id_configured() -> None:
    """Raise ValueError when postgres backend is on but no user id is configured."""
    from app.services.crash_store import uses_postgres_crash_store

    if uses_postgres_crash_store() and not resolve_user_id(required=False):
        raise ValueError(_POSTGRES_USER_ID_MSG)
