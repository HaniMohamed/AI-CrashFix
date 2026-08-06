from __future__ import annotations

import json
import sqlite3
from datetime import datetime
from typing import Any

from app.services.app_settings_store import resolve_app_settings_db_path
from app.services.sqlite_util import (
    connect_sqlite,
    mark_schema_ensured,
    schema_needs_ensure,
)


class SqliteAppSettingsStore:
    """SQLite-backed global settings (legacy single-machine schema)."""

    backend = "sqlite"

    def __init__(self, db_path: str | None = None) -> None:
        self.db_path = resolve_app_settings_db_path(db_path)
        self._cache: dict[str, Any] | None = None
        self._ensure_schema()

    def _connect(self):
        return connect_sqlite(self.db_path)

    def _ensure_schema(self) -> None:
        if not schema_needs_ensure(f"app_settings:{self.db_path}"):
            return
        with self._connect() as conn:
            conn.execute(
                """
                CREATE TABLE IF NOT EXISTS app_settings (
                    k TEXT PRIMARY KEY,
                    v TEXT,
                    updated_at TEXT
                )
                """
            )
            conn.commit()
        mark_schema_ensured(f"app_settings:{self.db_path}")

    def _invalidate_cache(self) -> None:
        self._cache = None

    def get_all(self) -> dict[str, Any]:
        if self._cache is not None:
            return dict(self._cache)

        out: dict[str, Any] = {}
        with self._connect() as conn:
            rows = conn.execute("SELECT k, v FROM app_settings").fetchall()
        for key, raw in rows:
            k = str(key or "").strip()
            if not k:
                continue
            if raw is None:
                out[k] = None
                continue
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
        now = datetime.utcnow().isoformat()
        payload = json.dumps(v, ensure_ascii=False)
        with self._connect() as conn:
            conn.execute(
                """
                INSERT INTO app_settings(k, v, updated_at)
                VALUES (?, ?, ?)
                ON CONFLICT(k) DO UPDATE SET
                  v = excluded.v,
                  updated_at = excluded.updated_at
                """,
                (key, payload, now),
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
            row = conn.execute(
                "SELECT updated_at FROM app_settings ORDER BY datetime(updated_at) DESC LIMIT 1"
            ).fetchone()
        if not row:
            return None
        v = row[0]
        return str(v).strip() or None
