from __future__ import annotations

import threading
from typing import Any, ClassVar, Protocol

from app.services.auth_models import AuthSessionRecord, AuthUserRecord


class AuthStoreBackend(Protocol):
    backend: str

    def count_users(self) -> int: ...
    def get_user_by_id(self, user_id: str) -> AuthUserRecord | None: ...
    def get_user_by_username(self, username: str) -> AuthUserRecord | None: ...
    def list_users(self) -> list[AuthUserRecord]: ...
    def create_user(
        self,
        *,
        username: str,
        tenant_user_id: str,
        role: str,
        password_hash: str,
        must_change_password: bool = True,
        created_by_user_id: str | None = None,
    ) -> AuthUserRecord: ...
    def update_user_password(
        self,
        user_id: str,
        password_hash: str,
        *,
        must_change_password: bool = False,
    ) -> AuthUserRecord | None: ...
    def update_user_status(self, user_id: str, status: str) -> AuthUserRecord | None: ...
    def update_user_role(self, user_id: str, role: str) -> AuthUserRecord | None: ...
    def record_failed_login(self, user_id: str, locked_until: str | None) -> None: ...
    def clear_failed_login(self, user_id: str) -> None: ...
    def delete_user(self, user_id: str) -> bool: ...
    def create_session(
        self,
        *,
        user_id: str,
        token_hash: str,
        expires_at: str,
        user_agent: str | None = None,
    ) -> AuthSessionRecord: ...
    def get_session_by_token_hash(self, token_hash: str) -> AuthSessionRecord | None: ...
    def touch_session(self, session_id: str) -> None: ...
    def revoke_session(self, session_id: str) -> None: ...
    def revoke_all_sessions_for_user(self, user_id: str) -> None: ...
    def write_audit(
        self,
        *,
        actor_user_id: str | None,
        action: str,
        target_user_id: str | None = None,
        details: dict[str, Any] | None = None,
    ) -> None: ...
    def list_audit(self, limit: int = 100) -> list[dict[str, Any]]: ...
    def get_setting(self, key: str, default: str | None = None) -> str | None: ...
    def set_setting(self, key: str, value: str) -> None: ...
    def get_all_settings(self) -> dict[str, str]: ...


class AuthStore:
    """Facade for auth persistence (SQLite local or shared Postgres)."""

    _shared: ClassVar[AuthStore | None] = None
    _shared_lock: ClassVar[threading.Lock] = threading.Lock()

    def __new__(cls) -> AuthStore:
        with cls._shared_lock:
            if cls._shared is None:
                obj = super().__new__(cls)
                cls._shared = obj
                obj._singleton_ready = False  # type: ignore[attr-defined]
            return cls._shared

    def __init__(self) -> None:
        if getattr(self, "_singleton_ready", False):
            return
        from app.services.crash_store import uses_postgres_crash_store

        if uses_postgres_crash_store():
            from app.services.auth_store_postgres import PostgresAuthStore

            self._impl: AuthStoreBackend = PostgresAuthStore()
        else:
            from app.services.auth_store_sqlite import SqliteAuthStore

            self._impl = SqliteAuthStore()
        self.backend = self._impl.backend
        self._singleton_ready = True

    @classmethod
    def clear_shared_for_tests(cls) -> None:
        with cls._shared_lock:
            cls._shared = None

    def count_users(self) -> int:
        return self._impl.count_users()

    def get_user_by_id(self, user_id: str) -> AuthUserRecord | None:
        return self._impl.get_user_by_id(user_id)

    def get_user_by_username(self, username: str) -> AuthUserRecord | None:
        return self._impl.get_user_by_username(username)

    def list_users(self) -> list[AuthUserRecord]:
        return self._impl.list_users()

    def create_user(
        self,
        *,
        username: str,
        tenant_user_id: str,
        role: str,
        password_hash: str,
        must_change_password: bool = True,
        created_by_user_id: str | None = None,
    ) -> AuthUserRecord:
        return self._impl.create_user(
            username=username,
            tenant_user_id=tenant_user_id,
            role=role,
            password_hash=password_hash,
            must_change_password=must_change_password,
            created_by_user_id=created_by_user_id,
        )

    def update_user_password(
        self,
        user_id: str,
        password_hash: str,
        *,
        must_change_password: bool = False,
    ) -> AuthUserRecord | None:
        return self._impl.update_user_password(
            user_id, password_hash, must_change_password=must_change_password
        )

    def update_user_status(self, user_id: str, status: str) -> AuthUserRecord | None:
        return self._impl.update_user_status(user_id, status)

    def update_user_role(self, user_id: str, role: str) -> AuthUserRecord | None:
        return self._impl.update_user_role(user_id, role)

    def record_failed_login(self, user_id: str, locked_until: str | None) -> None:
        self._impl.record_failed_login(user_id, locked_until)

    def clear_failed_login(self, user_id: str) -> None:
        self._impl.clear_failed_login(user_id)

    def delete_user(self, user_id: str) -> bool:
        return self._impl.delete_user(user_id)

    def create_session(
        self,
        *,
        user_id: str,
        token_hash: str,
        expires_at: str,
        user_agent: str | None = None,
    ) -> AuthSessionRecord:
        return self._impl.create_session(
            user_id=user_id,
            token_hash=token_hash,
            expires_at=expires_at,
            user_agent=user_agent,
        )

    def get_session_by_token_hash(self, token_hash: str) -> AuthSessionRecord | None:
        return self._impl.get_session_by_token_hash(token_hash)

    def touch_session(self, session_id: str) -> None:
        self._impl.touch_session(session_id)

    def revoke_session(self, session_id: str) -> None:
        self._impl.revoke_session(session_id)

    def revoke_all_sessions_for_user(self, user_id: str) -> None:
        self._impl.revoke_all_sessions_for_user(user_id)

    def write_audit(
        self,
        *,
        actor_user_id: str | None,
        action: str,
        target_user_id: str | None = None,
        details: dict[str, Any] | None = None,
    ) -> None:
        self._impl.write_audit(
            actor_user_id=actor_user_id,
            action=action,
            target_user_id=target_user_id,
            details=details,
        )

    def list_audit(self, limit: int = 100) -> list[dict[str, Any]]:
        return self._impl.list_audit(limit=limit)

    def get_setting(self, key: str, default: str | None = None) -> str | None:
        return self._impl.get_setting(key, default=default)

    def set_setting(self, key: str, value: str) -> None:
        self._impl.set_setting(key, value)

    def get_all_settings(self) -> dict[str, str]:
        return self._impl.get_all_settings()
