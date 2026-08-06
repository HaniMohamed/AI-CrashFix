"""Authentication HTTP endpoints."""

from __future__ import annotations

import asyncio
from typing import Any, Dict, Optional

from fastapi import APIRouter, HTTPException, Request
from pydantic import BaseModel, Field

from app.api.auth_middleware import require_admin
from app.services.auth_context import get_current_session
from app.services.auth_service import AuthService
from app.services.repo_data_guard import is_repo_data_readonly
from app.services.user_context import ai_crash_fix_user_id_raw, normalize_user_id

router = APIRouter(prefix="/api/auth", tags=["auth"])


class BootstrapAdminRequest(BaseModel):
    username: str
    tenant_user_id: Optional[str] = None
    temp_password: Optional[str] = None


class LoginRequest(BaseModel):
    username: str
    password: str


class ChangePasswordRequest(BaseModel):
    current_password: Optional[str] = None
    new_password: str


class CreateUserRequest(BaseModel):
    username: str
    tenant_user_id: Optional[str] = None
    role: str = Field("user", description="admin or user")


class UpdateUserRequest(BaseModel):
    status: Optional[str] = None
    role: Optional[str] = None


class SecuritySettingsRequest(BaseModel):
    session_hours: Optional[int] = None
    max_failed_logins: Optional[int] = None
    lockout_minutes: Optional[int] = None
    min_password_length: Optional[int] = None


class RepoReadonlyRequest(BaseModel):
    repo_data_readonly: bool


def _svc() -> AuthService:
    return AuthService()


@router.get("/bootstrap-status")
async def bootstrap_status() -> Dict[str, Any]:
    def _run() -> Dict[str, Any]:
        try:
            return _svc().bootstrap_status()
        except Exception as exc:
            raise HTTPException(
                status_code=503,
                detail=f"Auth store unavailable: {exc}",
            ) from exc

    return await asyncio.to_thread(_run)


@router.post("/bootstrap-admin")
async def bootstrap_admin(req: BootstrapAdminRequest) -> Dict[str, Any]:
    def _run() -> Dict[str, Any]:
        tenant = req.tenant_user_id
        if not tenant:
            tenant = ai_crash_fix_user_id_raw() or req.username
        try:
            return _svc().bootstrap_admin(
                username=req.username,
                tenant_user_id=tenant,
                temp_password=req.temp_password,
            )
        except ValueError as exc:
            raise HTTPException(status_code=400, detail=str(exc)) from exc
        except Exception as exc:
            raise HTTPException(
                status_code=503,
                detail=f"Auth store unavailable: {exc}",
            ) from exc

    return await asyncio.to_thread(_run)


@router.post("/login")
async def login(req: LoginRequest, request: Request) -> Dict[str, Any]:
    ua = request.headers.get("user-agent")

    def _run() -> Dict[str, Any]:
        try:
            return _svc().login(
                req.username,
                req.password,
                user_agent=ua,
            )
        except ValueError as exc:
            raise HTTPException(status_code=401, detail=str(exc)) from exc
        except Exception as exc:
            raise HTTPException(
                status_code=503,
                detail=f"Auth store unavailable: {exc}",
            ) from exc

    return await asyncio.to_thread(_run)


@router.post("/logout")
async def logout() -> Dict[str, Any]:
    session = get_current_session()
    if session is None:
        return {"ok": True}

    def _run() -> None:
        _svc().logout(session.session_id, session.user.id)

    await asyncio.to_thread(_run)
    return {"ok": True}


@router.get("/me")
async def me() -> Dict[str, Any]:
    session = get_current_session()
    if session is None:
        raise HTTPException(status_code=401, detail="Not authenticated")
    return {"user": session.user.to_public_dict()}


@router.post("/change-password")
async def change_password(req: ChangePasswordRequest) -> Dict[str, Any]:
    session = get_current_session()
    if session is None:
        raise HTTPException(status_code=401, detail="Not authenticated")

    def _run() -> Dict[str, Any]:
        try:
            user = _svc().change_password(
                session.user,
                current_password=req.current_password,
                new_password=req.new_password,
            )
            return {"ok": True, "user": user.to_public_dict()}
        except ValueError as exc:
            raise HTTPException(status_code=400, detail=str(exc)) from exc

    return await asyncio.to_thread(_run)


@router.get("/users")
async def list_users() -> Dict[str, Any]:
    require_admin()
    users = await asyncio.to_thread(_svc().list_users_public)
    return {"users": users}


@router.post("/users")
async def create_user(req: CreateUserRequest) -> Dict[str, Any]:
    session = get_current_session()
    if session is None:
        raise HTTPException(status_code=401, detail="Not authenticated")

    def _run() -> Dict[str, Any]:
        try:
            tenant = req.tenant_user_id
            if tenant:
                tenant = normalize_user_id(tenant)
            return _svc().create_user(
                session.user,
                username=req.username,
                tenant_user_id=tenant,
                role=req.role,
            )
        except PermissionError as exc:
            raise HTTPException(status_code=403, detail=str(exc)) from exc
        except ValueError as exc:
            raise HTTPException(status_code=400, detail=str(exc)) from exc

    return await asyncio.to_thread(_run)


@router.patch("/users/{user_id}")
async def update_user(user_id: str, req: UpdateUserRequest) -> Dict[str, Any]:
    session = get_current_session()
    if session is None:
        raise HTTPException(status_code=401, detail="Not authenticated")

    def _run() -> Dict[str, Any]:
        try:
            user = _svc().update_user(
                session.user,
                user_id,
                status=req.status,
                role=req.role,
            )
            return {"user": user.to_public_dict()}
        except PermissionError as exc:
            raise HTTPException(status_code=403, detail=str(exc)) from exc
        except ValueError as exc:
            raise HTTPException(status_code=400, detail=str(exc)) from exc

    return await asyncio.to_thread(_run)


@router.delete("/users/{user_id}")
async def delete_user(user_id: str) -> Dict[str, Any]:
    session = get_current_session()
    if session is None:
        raise HTTPException(status_code=401, detail="Not authenticated")

    def _run() -> Dict[str, Any]:
        try:
            _svc().delete_user(session.user, user_id)
            return {"ok": True}
        except PermissionError as exc:
            raise HTTPException(status_code=403, detail=str(exc)) from exc
        except ValueError as exc:
            raise HTTPException(status_code=400, detail=str(exc)) from exc

    await asyncio.to_thread(_run)
    return {"ok": True}


@router.post("/users/{user_id}/reset-password")
async def reset_user_password(user_id: str) -> Dict[str, Any]:
    session = get_current_session()
    if session is None:
        raise HTTPException(status_code=401, detail="Not authenticated")

    def _run() -> Dict[str, Any]:
        try:
            return _svc().reset_password(session.user, user_id)
        except PermissionError as exc:
            raise HTTPException(status_code=403, detail=str(exc)) from exc
        except ValueError as exc:
            raise HTTPException(status_code=400, detail=str(exc)) from exc

    return await asyncio.to_thread(_run)


@router.get("/audit")
async def audit_log(limit: int = 100) -> Dict[str, Any]:
    session = get_current_session()
    if session is None:
        raise HTTPException(status_code=401, detail="Not authenticated")

    def _run() -> list[dict[str, Any]]:
        try:
            return _svc().list_audit(session.user, limit=limit)
        except PermissionError as exc:
            raise HTTPException(status_code=403, detail=str(exc)) from exc

    entries = await asyncio.to_thread(_run)
    return {"entries": entries}


@router.get("/security-settings")
async def get_security_settings() -> Dict[str, Any]:
    require_admin()
    settings = await asyncio.to_thread(_svc().get_security_settings)
    readonly = await asyncio.to_thread(is_repo_data_readonly)
    return {"settings": settings, "repo_data_readonly": readonly}


@router.post("/security-settings")
async def update_security_settings(req: SecuritySettingsRequest) -> Dict[str, Any]:
    session = get_current_session()
    if session is None:
        raise HTTPException(status_code=401, detail="Not authenticated")

    def _run() -> Dict[str, Any]:
        try:
            return _svc().update_security_settings(
                session.user,
                session_hours=req.session_hours,
                max_failed_logins=req.max_failed_logins,
                lockout_minutes=req.lockout_minutes,
                min_password_length=req.min_password_length,
            )
        except PermissionError as exc:
            raise HTTPException(status_code=403, detail=str(exc)) from exc

    settings = await asyncio.to_thread(_run)
    return {"settings": settings}


@router.post("/security-settings/repo-readonly")
async def set_repo_readonly(req: RepoReadonlyRequest) -> Dict[str, Any]:
    session = get_current_session()
    if session is None:
        raise HTTPException(status_code=401, detail="Not authenticated")
    if session.user.role != "admin":
        raise HTTPException(status_code=403, detail="Admin only")

    def _run() -> None:
        from app.services.app_settings_store import AppSettingsStore
        from app.services.repo_data_guard import SETTINGS_KEY_REPO_DATA_READONLY

        AppSettingsStore().set(k=SETTINGS_KEY_REPO_DATA_READONLY, v=bool(req.repo_data_readonly))
        from app.services.auth_store import AuthStore

        AuthStore().write_audit(
            actor_user_id=session.user.id,
            action="set_repo_readonly",
            details={"repo_data_readonly": bool(req.repo_data_readonly)},
        )

    await asyncio.to_thread(_run)
    return {"ok": True, "repo_data_readonly": bool(req.repo_data_readonly)}
