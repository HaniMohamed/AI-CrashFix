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
    return (method.upper(), path) in _PUBLIC_EXACT


def allows_password_change_pending(method: str, path: str) -> bool:
    return is_public_route(method, path) or (method.upper(), path) in _PASSWORD_CHANGE_ALLOWED


async def auth_middleware(request: Request, call_next: Callable) -> Response:
    method = request.method.upper()
    path = request.url.path

    if is_public_route(method, path):
        token = _extract_bearer(request)
        if token:
            session = AuthService().authenticate_token(token)
            set_current_session(session)
        else:
            set_current_session(None)
        response = await call_next(request)
        set_current_session(None)
        return response

    token = _extract_bearer(request)
    if not token:
        return JSONResponse(
            status_code=401,
            content={"detail": "Authentication required"},
        )

    service = AuthService()
    session = service.authenticate_token(token)
    if session is None:
        return JSONResponse(
            status_code=401,
            content={"detail": "Invalid or expired session"},
        )

    set_current_session(session)

    if session.user.must_change_password and not allows_password_change_pending(method, path):
        return JSONResponse(
            status_code=403,
            content={"detail": "Password change required", "must_change_password": True},
        )

    response = await call_next(request)
    set_current_session(None)
    return response


def require_admin() -> None:
    session = get_current_session()
    if session is None or session.user.role != "admin":
        raise HTTPException(status_code=403, detail="Admin only")
