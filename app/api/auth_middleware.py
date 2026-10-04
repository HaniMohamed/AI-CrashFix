"""FastAPI auth middleware and dependencies."""

from __future__ import annotations

from typing import Callable

from fastapi import HTTPException, Request
from starlette.responses import JSONResponse, Response

from app.services.auth_context import (
    AuthenticatedSession,
    get_current_session,
    set_current_session,
)
from app.services.auth_service import AuthService

# Exact paths (no trailing slash) allowed without authentication.
_PUBLIC_EXACT: frozenset[tuple[str, str]] = frozenset(
    {
        ("GET", "/api/health"),
        ("GET", "/api/auth/bootstrap-status"),
        ("POST", "/api/auth/bootstrap-admin"),
        ("POST", "/api/auth/login"),
    }
)

_SETUP_STORE_ROUTES: frozenset[tuple[str, str]] = frozenset(
    {
        ("GET", "/api/setup/store"),
        ("POST", "/api/setup/store"),
        ("POST", "/api/setup/test/store"),
    }
)

# Allowed while must_change_password is true (besides public routes).
_PASSWORD_CHANGE_ALLOWED: frozenset[tuple[str, str]] = frozenset(
    {
        ("POST", "/api/auth/change-password"),
        ("POST", "/api/auth/logout"),
        ("GET", "/api/auth/me"),
    }
)


def _extract_bearer(request: Request) -> str | None:
    auth = (request.headers.get("authorization") or "").strip()
    if auth.lower().startswith("bearer "):
        return auth[7:].strip() or None
    return None


def is_public_route(method: str, path: str) -> bool:
    pair = (method.upper(), path)
    if pair in _PUBLIC_EXACT:
        return True
    if pair in _SETUP_STORE_ROUTES:
        try:
            from app.services.store_bootstrap import can_configure_store_without_auth

            return can_configure_store_without_auth()
        except Exception:
            return True
    return False


def allows_password_change_pending(method: str, path: str) -> bool:
    return is_public_route(method, path) or (method.upper(), path) in _PASSWORD_CHANGE_ALLOWED


async def auth_middleware(request: Request, call_next: Callable) -> Response:
    method = request.method.upper()
    path = request.url.path

    def _authenticate(token: str | None) -> AuthenticatedSession | None | str:
        """Return session, None if invalid token, or ``'store_error'`` on store failure."""
        if not token:
            return None
        try:
            return AuthService().authenticate_token(token)
        except Exception:
            # Store outages must not look like "logged out" (401) — that kicks the UI
            # back to the login screen in a loop.
            return "store_error"

    if is_public_route(method, path):
        token = _extract_bearer(request)
        session = _authenticate(token)
        set_current_session(session if not isinstance(session, str) else None)
        try:
            response = await call_next(request)
        finally:
            set_current_session(None)
        return response

    token = _extract_bearer(request)
    if not token:
        return JSONResponse(
            status_code=401,
            content={"detail": "Authentication required"},
        )

    session = _authenticate(token)
    if session == "store_error":
        return JSONResponse(
            status_code=503,
            content={"detail": "Auth store temporarily unavailable"},
        )
    if session is None:
        return JSONResponse(
            status_code=401,
            content={"detail": "Invalid or expired session"},
        )

    set_current_session(session)

    if session.user.must_change_password and not allows_password_change_pending(method, path):
        set_current_session(None)
        return JSONResponse(
            status_code=403,
            content={"detail": "Password change required", "must_change_password": True},
        )

    try:
        response = await call_next(request)
    finally:
        set_current_session(None)
    return response


def require_admin() -> None:
    session = get_current_session()
    if session is None or session.user.role != "admin":
        raise HTTPException(status_code=403, detail="Admin only")
