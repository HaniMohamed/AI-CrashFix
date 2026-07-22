from __future__ import annotations

import json
from datetime import datetime
from typing import Any

import psycopg
from psycopg.rows import dict_row
from psycopg.types.json import Json

from app.config import AI_CRASH_FIX_CRASH_DB_URL
from app.services.postgres_schema import connect_postgres, ensure_app_postgres_schema
from app.services.user_context import resolve_user_id


def _db_url() -> str:
    url = (AI_CRASH_FIX_CRASH_DB_URL or "").strip()
    if not url:
        raise ValueError(
            "AI_CRASH_FIX_CRASH_DB_URL is required when AI_CRASH_FIX_CRASH_STORE_BACKEND=postgres"
        )
    return url


class PostgresAppSettingsStore:
    """Postgres-backed settings scoped by normalized user_id."""

    backend = "postgres"

    def __init__(self) -> None:
        self.user_id = resolve_user_id(required=True)
        assert self.user_id is not None
        self.db_path = _db_url()
        with self._connect() as conn:
            ensure_app_postgres_schema(conn)
        self._cache: dict[str, Any] | None = None

    def _connect(self) -> psycopg.Connection:
        return connect_postgres(self.db_path, row_factory=dict_row)

    def _invalidate_cache(self) -> None:
        self._cache = None

    def get_all(self) -> dict[str, Any]:
        if self._cache is not None:
            return dict(self._cache)

        out: dict[str, Any] = {}
        with self._connect() as conn:
            with conn.cursor() as cur:
                cur.execute(
                    "SELECT k, v FROM app_settings WHERE user_id = %s",
                    (self.user_id,),
                )
                rows = cur.fetchall()
        for row in rows:
            k = str(row.get("k") or "").strip()
            if not k:
                continue
            raw = row.get("v")
            if raw is None:
                out[k] = None
            elif isinstance(raw, (dict, list, str, int, float, bool)):
                out[k] = raw
            else:
                try:
                    out[k] = json.loads(str(raw))
                except Exception:
                    out[k] = None

        self._cache = out
        return dict(out)

    def set(self, *, k: str, v: Any) -> None:
        key = (k or "").strip()
        if not key:
            raise ValueError("k is required")
        now = datetime.utcnow()
        with self._connect() as conn:
            with conn.cursor() as cur:
                cur.execute(
                    """
                    INSERT INTO app_settings(user_id, k, v, updated_at)
                    VALUES (%s, %s, %s, %s)
                    ON CONFLICT (user_id, k) DO UPDATE SET
                      v = EXCLUDED.v,
                      updated_at = EXCLUDED.updated_at
                    """,
                    (self.user_id, key, Json(v), now),
                )
            conn.commit()
        self._invalidate_cache()

    def get(self, *, k: str) -> Any | None:
        key = (k or "").strip()
        if not key:
            return None
        return self.get_all().get(key)

    def get_updated_at(self) -> str | None:
        with self._connect() as conn:
            with conn.cursor() as cur:
                cur.execute(
                    """
                    SELECT updated_at
                    FROM app_settings
                    WHERE user_id = %s
                    ORDER BY updated_at DESC NULLS LAST
                    LIMIT 1
                    """,
                    (self.user_id,),
                )
                row = cur.fetchone()
        if not row:
            return None
        v = row.get("updated_at")
        if v is None:
            return None
        if hasattr(v, "isoformat"):
            return v.isoformat()
        s = str(v).strip()
        return s or None
