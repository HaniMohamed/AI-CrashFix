from __future__ import annotations

import json
import os
import uuid
from datetime import datetime, timezone
from typing import Any

import psycopg
from psycopg.rows import dict_row
from psycopg.types.json import Json

from app.config import AI_CRASH_FIX_CRASH_DB_URL
from app.services.auth_models import AuthSessionRecord, AuthUserRecord
from app.services.auth_schema import AUTH_SCHEMA_SQL_POSTGRES
from app.services.postgres_schema import connect_postgres, ensure_app_postgres_schema


def _db_url() -> str:
    url = (
        (os.getenv("AI_CRASH_FIX_CRASH_DB_URL") or "").strip()
        or (AI_CRASH_FIX_CRASH_DB_URL or "").strip()
    )
    if not url:
        raise ValueError(
            "AI_CRASH_FIX_CRASH_DB_URL is required when AI_CRASH_FIX_CRASH_STORE_BACKEND=postgres"
        )
    return url


def _now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def _row_to_user(row: dict[str, Any]) -> AuthUserRecord:
    return AuthUserRecord(
        id=str(row["id"]),
        username=str(row["username"]),
        tenant_user_id=str(row["tenant_user_id"]),
        role=str(row["role"]),
        status=str(row["status"]),
        password_hash=str(row["password_hash"]),
        must_change_password=bool(row["must_change_password"]),
        password_changed_at=row.get("password_changed_at"),
        failed_login_count=int(row.get("failed_login_count") or 0),
        locked_until=row.get("locked_until"),
        created_at=str(row.get("created_at") or "") or None,
        updated_at=str(row.get("updated_at") or "") or None,
        created_by_user_id=row.get("created_by_user_id"),
    )


class PostgresAuthStore:
    backend = "postgres"

    def __init__(self) -> None:
        self.db_path = _db_url()
        with self._connect() as conn:
            ensure_app_postgres_schema(conn)
            self._ensure_auth_schema(conn)

    def _connect(self) -> psycopg.Connection:
        return connect_postgres(self.db_path, row_factory=dict_row)

    def _ensure_auth_schema(self, conn: psycopg.Connection) -> None:
        with conn.cursor() as cur:
            for statement in AUTH_SCHEMA_SQL_POSTGRES.split(";"):
                s = statement.strip()
                if s:
                    cur.execute(s)
        conn.commit()

    def count_users(self) -> int:
        with self._connect() as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT COUNT(*) AS c FROM auth_users")
                row = cur.fetchone()
        return int(row["c"] or 0)

    def get_user_by_id(self, user_id: str) -> AuthUserRecord | None:
        with self._connect() as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT * FROM auth_users WHERE id = %s", (user_id,))
                row = cur.fetchone()
        return _row_to_user(row) if row else None

    def get_user_by_username(self, username: str) -> AuthUserRecord | None:
        with self._connect() as conn:
            with conn.cursor() as cur:
                cur.execute(
                    "SELECT * FROM auth_users WHERE username = %s",
                    (username.strip().lower(),),
                )
                row = cur.fetchone()
        return _row_to_user(row) if row else None

    def list_users(self) -> list[AuthUserRecord]:
        with self._connect() as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT * FROM auth_users ORDER BY username")
                rows = cur.fetchall()
        return [_row_to_user(r) for r in rows]

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
        uid = str(uuid.uuid4())
        now = _now_iso()
        uname = username.strip().lower()
        tenant = tenant_user_id.strip().lower()
        with self._connect() as conn:
            with conn.cursor() as cur:
                cur.execute(
                    """
                    INSERT INTO auth_users (
                      id, username, tenant_user_id, role, status, password_hash,
                      must_change_password, failed_login_count, created_at, updated_at,
                      created_by_user_id
                    ) VALUES (%s, %s, %s, %s, 'active', %s, %s, 0, %s, %s, %s)
                    """,
                    (
                        uid,
                        uname,
                        tenant,
                        role,
                        password_hash,
                        must_change_password,
                        now,
                        now,
                        created_by_user_id,
                    ),
                )
            conn.commit()
        user = self.get_user_by_id(uid)
        assert user is not None
        return user

    def update_user_password(
        self,
        user_id: str,
        password_hash: str,
        *,
        must_change_password: bool = False,
    ) -> AuthUserRecord | None:
        now = _now_iso()
        with self._connect() as conn:
            with conn.cursor() as cur:
                cur.execute(
                    """
                    UPDATE auth_users SET
                      password_hash = %s,
                      must_change_password = %s,
                      password_changed_at = %s,
                      failed_login_count = 0,
                      locked_until = NULL,
                      updated_at = %s
                    WHERE id = %s
                    """,
                    (password_hash, must_change_password, now, now, user_id),
                )
            conn.commit()
        return self.get_user_by_id(user_id)

    def update_user_status(self, user_id: str, status: str) -> AuthUserRecord | None:
        now = _now_iso()
        with self._connect() as conn:
            with conn.cursor() as cur:
                cur.execute(
                    "UPDATE auth_users SET status = %s, updated_at = %s WHERE id = %s",
                    (status, now, user_id),
                )
            conn.commit()
        return self.get_user_by_id(user_id)

    def update_user_role(self, user_id: str, role: str) -> AuthUserRecord | None:
        now = _now_iso()
        with self._connect() as conn:
            with conn.cursor() as cur:
                cur.execute(
                    "UPDATE auth_users SET role = %s, updated_at = %s WHERE id = %s",
                    (role, now, user_id),
                )
            conn.commit()
        return self.get_user_by_id(user_id)

    def record_failed_login(self, user_id: str, locked_until: str | None) -> None:
        now = _now_iso()
        with self._connect() as conn:
            with conn.cursor() as cur:
                cur.execute(
                    """
                    UPDATE auth_users SET
                      failed_login_count = failed_login_count + 1,
                      locked_until = %s,
                      updated_at = %s
                    WHERE id = %s
                    """,
                    (locked_until, now, user_id),
                )
            conn.commit()

    def clear_failed_login(self, user_id: str) -> None:
        now = _now_iso()
        with self._connect() as conn:
            with conn.cursor() as cur:
                cur.execute(
                    """
                    UPDATE auth_users SET
                      failed_login_count = 0,
                      locked_until = NULL,
                      updated_at = %s
                    WHERE id = %s
                    """,
                    (now, user_id),
                )
            conn.commit()

    def delete_user(self, user_id: str) -> bool:
        with self._connect() as conn:
            with conn.cursor() as cur:
                cur.execute("DELETE FROM auth_users WHERE id = %s", (user_id,))
                deleted = cur.rowcount > 0
            conn.commit()
        return deleted

    def create_session(
        self,
        *,
        user_id: str,
        token_hash: str,
        expires_at: str,
        user_agent: str | None = None,
    ) -> AuthSessionRecord:
        sid = str(uuid.uuid4())
        now = _now_iso()
        with self._connect() as conn:
            with conn.cursor() as cur:
                cur.execute(
                    """
                    INSERT INTO auth_sessions (
                      id, user_id, token_hash, expires_at, created_at, last_seen_at, user_agent
                    ) VALUES (%s, %s, %s, %s, %s, %s, %s)
                    """,
                    (sid, user_id, token_hash, expires_at, now, now, user_agent),
                )
            conn.commit()
        return AuthSessionRecord(
            id=sid,
            user_id=user_id,
            token_hash=token_hash,
            expires_at=expires_at,
            created_at=now,
            last_seen_at=now,
            user_agent=user_agent,
        )

    def get_session_by_token_hash(self, token_hash: str) -> AuthSessionRecord | None:
        with self._connect() as conn:
            with conn.cursor() as cur:
                cur.execute(
                    "SELECT * FROM auth_sessions WHERE token_hash = %s",
                    (token_hash,),
                )
                row = cur.fetchone()
        if not row:
            return None
        return AuthSessionRecord(
            id=str(row["id"]),
            user_id=str(row["user_id"]),
            token_hash=str(row["token_hash"]),
            expires_at=str(row["expires_at"]),
            revoked_at=row.get("revoked_at"),
            created_at=row.get("created_at"),
            last_seen_at=row.get("last_seen_at"),
            user_agent=row.get("user_agent"),
        )

    def touch_session(self, session_id: str) -> None:
        now = _now_iso()
        with self._connect() as conn:
            with conn.cursor() as cur:
                cur.execute(
                    "UPDATE auth_sessions SET last_seen_at = %s WHERE id = %s",
                    (now, session_id),
                )
            conn.commit()

    def revoke_session(self, session_id: str) -> None:
        now = _now_iso()
        with self._connect() as conn:
            with conn.cursor() as cur:
                cur.execute(
                    "UPDATE auth_sessions SET revoked_at = %s WHERE id = %s",
                    (now, session_id),
                )
            conn.commit()

    def revoke_all_sessions_for_user(self, user_id: str) -> None:
        now = _now_iso()
        with self._connect() as conn:
            with conn.cursor() as cur:
                cur.execute(
                    """
                    UPDATE auth_sessions SET revoked_at = %s
                    WHERE user_id = %s AND revoked_at IS NULL
                    """,
                    (now, user_id),
                )
            conn.commit()

    def write_audit(
        self,
        *,
        actor_user_id: str | None,
        action: str,
        target_user_id: str | None = None,
        details: dict[str, Any] | None = None,
    ) -> None:
        aid = str(uuid.uuid4())
        now = _now_iso()
        with self._connect() as conn:
            with conn.cursor() as cur:
                cur.execute(
                    """
                    INSERT INTO auth_audit_log (
                      id, actor_user_id, action, target_user_id, details, created_at
                    ) VALUES (%s, %s, %s, %s, %s, %s)
                    """,
                    (
                        aid,
                        actor_user_id,
                        action,
                        target_user_id,
                        Json(details or {}),
                        now,
                    ),
                )
            conn.commit()

    def list_audit(self, limit: int = 100) -> list[dict[str, Any]]:
        with self._connect() as conn:
            with conn.cursor() as cur:
                cur.execute(
                    """
                    SELECT id, actor_user_id, action, target_user_id, details, created_at
                    FROM auth_audit_log ORDER BY created_at DESC LIMIT %s
                    """,
                    (max(1, min(limit, 500)),),
                )
                rows = cur.fetchall()
        return [dict(r) for r in rows]

    def get_setting(self, key: str, default: str | None = None) -> str | None:
        with self._connect() as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT v FROM auth_settings WHERE k = %s", (key,))
                row = cur.fetchone()
        if not row:
            return default
        return str(row["v"])

    def set_setting(self, key: str, value: str) -> None:
        now = _now_iso()
        with self._connect() as conn:
            with conn.cursor() as cur:
                cur.execute(
                    """
                    INSERT INTO auth_settings (k, v, updated_at) VALUES (%s, %s, %s)
                    ON CONFLICT (k) DO UPDATE SET v = EXCLUDED.v, updated_at = EXCLUDED.updated_at
                    """,
                    (key, value, now),
                )
            conn.commit()

    def get_all_settings(self) -> dict[str, str]:
        with self._connect() as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT k, v FROM auth_settings")
                rows = cur.fetchall()
        return {str(r["k"]): str(r["v"]) for r in rows}
