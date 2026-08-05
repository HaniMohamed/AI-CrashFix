"""Request-scoped authenticated user context."""

from __future__ import annotations

from contextvars import ContextVar
from dataclasses import dataclass
from typing import Any

from app.services.auth_models import AuthUserRecord


@dataclass(frozen=True)
class AuthenticatedSession:
    user: AuthUserRecord
    session_id: str
    token: str


_current_session: ContextVar[AuthenticatedSession | None] = ContextVar(
    "fixora_auth_session", default=None
)


def set_current_session(session: AuthenticatedSession | None) -> None:
    _current_session.set(session)


def get_current_session() -> AuthenticatedSession | None:
    return _current_session.get()


def get_current_user() -> AuthUserRecord | None:
    sess = get_current_session()
    return sess.user if sess else None


def current_user_public() -> dict[str, Any] | None:
    user = get_current_user()
    return user.to_public_dict() if user else None
