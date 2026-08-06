from __future__ import annotations

import json
import sqlite3
import uuid
from datetime import datetime, timezone
from typing import Any

from app.services.auth_models import AuthSessionRecord, AuthUserRecord
from app.services.auth_schema import AUTH_SCHEMA_SQL_SQLITE
from app.services.app_settings_store import resolve_app_settings_db_path
from app.services.sqlite_util import connect_sqlite, mark_schema_ensured, schema_needs_ensure


def _now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def _row_to_user(row: sqlite3.Row | tuple) -> AuthUserRecord:
    if isinstance(row, sqlite3.Row):
        d = dict(row)
    else:
        keys = [
            "id",
            "username",
            "tenant_user_id",
            "role",
            "status",
            "password_hash",
            "must_change_password",
            "password_changed_at",
            "failed_login_count",
            "locked_until",
            "created_at",
            "updated_at",
            "created_by_user_id",
        ]
        d = dict(zip(keys, row))
    return AuthUserRecord(
        id=str(d["id"]),
        username=str(d["username"]),
        tenant_user_id=str(d["tenant_user_id"]),
        role=str(d["role"]),
        status=str(d["status"]),
        password_hash=str(d["password_hash"]),
        must_change_password=bool(d["must_change_password"]),
        password_changed_at=d.get("password_changed_at"),
        failed_login_count=int(d.get("failed_login_count") or 0),
        locked_until=d.get("locked_until"),
        created_at=d.get("created_at"),
        updated_at=d.get("updated_at"),
        created_by_user_id=d.get("created_by_user_id"),
    )


class SqliteAuthStore:
    backend = "sqlite"

    def __init__(self, db_path: str | None = None) -> None:
        self.db_path = resolve_app_settings_db_path(db_path)
        self._ensure_schema()

    def _connect(self):
        return connect_sqlite(self.db_path, row_factory=sqlite3.Row)

    def _ensure_schema(self) -> None:
        key = f"auth:{self.db_path}"
        if not schema_needs_ensure(key):
            return
        with self._connect() as conn:
            for stmt in AUTH_SCHEMA_SQL_SQLITE.split(";"):
                s = stmt.strip()
                if s:
                    conn.execute(s)
            conn.commit()
        mark_schema_ensured(key)

    def count_users(self) -> int:
        with self._connect() as conn:
            row = conn.execute("SELECT COUNT(*) FROM auth_users").fetchone()
            return int(row[0] or 0)

    def get_user_by_id(self, user_id: str) -> AuthUserRecord | None:
        with self._connect() as conn:
            row = conn.execute(
                "SELECT * FROM auth_users WHERE id = ?", (user_id,)
            ).fetchone()
        return _row_to_user(row) if row else None

    def get_user_by_username(self, username: str) -> AuthUserRecord | None:
        with self._connect() as conn:
            row = conn.execute(
                "SELECT * FROM auth_users WHERE username = ?",
                (username.strip().lower(),),
            ).fetchone()
        return _row_to_user(row) if row else None

    def list_users(self) -> list[AuthUserRecord]:
        with self._connect() as conn:
            rows = conn.execute(
                "SELECT * FROM auth_users ORDER BY username"
            ).fetchall()
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
            conn.execute(
                """
                INSERT INTO auth_users (
                  id, username, tenant_user_id, role, status, password_hash,
                  must_change_password, failed_login_count, created_at, updated_at,
                  created_by_user_id
                ) VALUES (?, ?, ?, ?, 'active', ?, ?, 0, ?, ?, ?)
                """,
                (
                    uid,
                    uname,
                    tenant,
                    role,
                    password_hash,
                    1 if must_change_password else 0,
                    now,
                    now,
                    created_by_user_id,
                ),
            )
            conn.commit()
        return self.get_user_by_id(uid)  # type: ignore[return-value]

    def update_user_password(
        self,
        user_id: str,
        password_hash: str,
        *,
        must_change_password: bool = False,
    ) -> AuthUserRecord | None:
        now = _now_iso()
        with self._connect() as conn:
            conn.execute(
                """
                UPDATE auth_users SET
                  password_hash = ?,
                  must_change_password = ?,
                  password_changed_at = ?,
                  failed_login_count = 0,
                  locked_until = NULL,
                  updated_at = ?
                WHERE id = ?
                """,
                (
                    password_hash,
                    1 if must_change_password else 0,
                    now,
                    now,
                    user_id,
                ),
            )
            conn.commit()
        return self.get_user_by_id(user_id)

    def update_user_status(self, user_id: str, status: str) -> AuthUserRecord | None:
        now = _now_iso()
        with self._connect() as conn:
            conn.execute(
                "UPDATE auth_users SET status = ?, updated_at = ? WHERE id = ?",
                (status, now, user_id),
            )
            conn.commit()
        return self.get_user_by_id(user_id)

    def update_user_role(self, user_id: str, role: str) -> AuthUserRecord | None:
        now = _now_iso()
        with self._connect() as conn:
            conn.execute(
                "UPDATE auth_users SET role = ?, updated_at = ? WHERE id = ?",
                (role, now, user_id),
            )
            conn.commit()
        return self.get_user_by_id(user_id)

    def record_failed_login(self, user_id: str, locked_until: str | None) -> None:
        now = _now_iso()
        with self._connect() as conn:
            conn.execute(
                """
                UPDATE auth_users SET
                  failed_login_count = failed_login_count + 1,
                  locked_until = ?,
                  updated_at = ?
                WHERE id = ?
                """,
                (locked_until, now, user_id),
            )
            conn.commit()

    def clear_failed_login(self, user_id: str) -> None:
        now = _now_iso()
        with self._connect() as conn:
            conn.execute(
                """
                UPDATE auth_users SET
                  failed_login_count = 0,
                  locked_until = NULL,
                  updated_at = ?
                WHERE id = ?
                """,
                (now, user_id),
            )
            conn.commit()

    def delete_user(self, user_id: str) -> bool:
        with self._connect() as conn:
            cur = conn.execute("DELETE FROM auth_users WHERE id = ?", (user_id,))
            conn.commit()
            return cur.rowcount > 0

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
            conn.execute(
                """
                INSERT INTO auth_sessions (
                  id, user_id, token_hash, expires_at, created_at, last_seen_at, user_agent
                ) VALUES (?, ?, ?, ?, ?, ?, ?)
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
            row = conn.execute(
                "SELECT * FROM auth_sessions WHERE token_hash = ?",
                (token_hash,),
            ).fetchone()
        if not row:
            return None
        d = dict(row)
        return AuthSessionRecord(
            id=str(d["id"]),
            user_id=str(d["user_id"]),
            token_hash=str(d["token_hash"]),
            expires_at=str(d["expires_at"]),
            revoked_at=d.get("revoked_at"),
            created_at=d.get("created_at"),
            last_seen_at=d.get("last_seen_at"),
            user_agent=d.get("user_agent"),
        )

    def touch_session(self, session_id: str) -> None:
        now = _now_iso()
        with self._connect() as conn:
            conn.execute(
                "UPDATE auth_sessions SET last_seen_at = ? WHERE id = ?",
                (now, session_id),
            )
            conn.commit()

    def revoke_session(self, session_id: str) -> None:
        now = _now_iso()
        with self._connect() as conn:
            conn.execute(
                "UPDATE auth_sessions SET revoked_at = ? WHERE id = ?",
                (now, session_id),
            )
            conn.commit()

    def revoke_all_sessions_for_user(self, user_id: str) -> None:
        now = _now_iso()
        with self._connect() as conn:
            conn.execute(
                "UPDATE auth_sessions SET revoked_at = ? WHERE user_id = ? AND revoked_at IS NULL",
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
        payload = json.dumps(details or {}, ensure_ascii=False)
        with self._connect() as conn:
            conn.execute(
                """
                INSERT INTO auth_audit_log (
                  id, actor_user_id, action, target_user_id, details, created_at
                ) VALUES (?, ?, ?, ?, ?, ?)
                """,
                (aid, actor_user_id, action, target_user_id, payload, now),
            )
            conn.commit()

    def list_audit(self, limit: int = 100) -> list[dict[str, Any]]:
        with self._connect() as conn:
            rows = conn.execute(
                """
                SELECT id, actor_user_id, action, target_user_id, details, created_at
                FROM auth_audit_log ORDER BY created_at DESC LIMIT ?
                """,
                (max(1, min(limit, 500)),),
            ).fetchall()
        out: list[dict[str, Any]] = []
        for row in rows:
            d = dict(row)
            details_raw = d.get("details")
            if isinstance(details_raw, str):
                try:
                    d["details"] = json.loads(details_raw)
                except json.JSONDecodeError:
                    d["details"] = {}
            out.append(d)
        return out

    def get_setting(self, key: str, default: str | None = None) -> str | None:
        with self._connect() as conn:
            row = conn.execute(
                "SELECT v FROM auth_settings WHERE k = ?", (key,)
            ).fetchone()
        if not row:
            return default
        return str(row[0])

    def set_setting(self, key: str, value: str) -> None:
        now = _now_iso()
        with self._connect() as conn:
            conn.execute(
                """
                INSERT INTO auth_settings (k, v, updated_at) VALUES (?, ?, ?)
                ON CONFLICT(k) DO UPDATE SET v = excluded.v, updated_at = excluded.updated_at
                """,
                (key, value, now),
            )
            conn.commit()

    def get_all_settings(self) -> dict[str, str]:
        with self._connect() as conn:
            rows = conn.execute("SELECT k, v FROM auth_settings").fetchall()
        return {str(k): str(v) for k, v in rows}
