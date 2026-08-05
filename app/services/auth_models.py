from __future__ import annotations

from dataclasses import dataclass
from typing import Any


@dataclass(frozen=True)
class AuthUserRecord:
    id: str
    username: str
    tenant_user_id: str
    role: str
    status: str
    must_change_password: bool
    password_hash: str
    password_changed_at: str | None = None
    failed_login_count: int = 0
    locked_until: str | None = None
    created_at: str | None = None
    updated_at: str | None = None
    created_by_user_id: str | None = None

    def to_public_dict(self) -> dict[str, Any]:
        return {
            "id": self.id,
            "username": self.username,
            "tenant_user_id": self.tenant_user_id,
            "role": self.role,
            "status": self.status,
            "must_change_password": self.must_change_password,
            "password_changed_at": self.password_changed_at,
            "created_at": self.created_at,
            "updated_at": self.updated_at,
        }


@dataclass(frozen=True)
class AuthSessionRecord:
    id: str
    user_id: str
    token_hash: str
    expires_at: str
    revoked_at: str | None = None
    created_at: str | None = None
    last_seen_at: str | None = None
    user_agent: str | None = None
