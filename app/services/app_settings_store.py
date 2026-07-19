from __future__ import annotations

import json
import os
import sqlite3
import threading
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Any, ClassVar

from app.services.sqlite_util import (
    connect_sqlite,
    mark_schema_ensured,
    schema_needs_ensure,
)


def _data_dir() -> Path | None:
    raw = (os.environ.get("AI_CRASH_FIX_DATA_DIR") or "").strip()
    if not raw:
        return None
    try:
        return Path(raw).expanduser().resolve()
    except Exception:
        return None


def resolve_app_settings_db_path(db_path: str | None = None) -> str:
    path = (db_path or os.environ.get("AI_CRASH_FIX_REPO_REGISTRY_DB") or "").strip()
    if not path:
        base = _data_dir()
        if base is not None:
            path = os.fspath((base / "db" / "repo_registry.db").resolve())
        else:
            path = "db/repo_registry.db"
    p = Path(path).expanduser().resolve()
    p.parent.mkdir(parents=True, exist_ok=True)
    return str(p)


@dataclass(frozen=True)
class AppSettingsSnapshot:
    # LLM
    llm_provider: str | None
    openai_model: str | None
    openai_url: str | None
    has_openai_api_key: bool
    gemini_model: str | None
    has_google_api_key: bool

    # Crashlytics/BigQuery (global defaults only)
    google_application_credentials: str | None
    bq_project_id: str | None
    firebase_console_project_id: str | None
    crashlytics_android_package_default: str | None
    crashlytics_ios_bundle_id_default: str | None

    # Jira (global defaults only; project key is repo-scoped)
    jira_server_url: str | None
    jira_verify_ssl: str | None
    has_jira_token: bool

    # GitLab (global defaults only; project is repo-scoped)
    gitlab_server_url: str | None
    gitlab_verify_ssl: str | None
    gitlab_ssl_ca_bundle: str | None
    has_gitlab_token: bool

    updated_at: str | None


class AppSettingsStore:
    """
    Global, backend-persisted settings (editable from UI) with .env fallback.

    Secrets are stored but never returned.

    One process-wide instance is reused per DB path so we do not open SQLite
    (and re-run schema checks) on every SettingsResolver / API call.
    """

    _shared: ClassVar[dict[str, AppSettingsStore]] = {}
    _shared_lock: ClassVar[threading.Lock] = threading.Lock()

    def __new__(cls, db_path: str | None = None) -> AppSettingsStore:
        path = resolve_app_settings_db_path(db_path)
        with cls._shared_lock:
            existing = cls._shared.get(path)
            if existing is not None:
                return existing
            obj = super().__new__(cls)
            cls._shared[path] = obj
            obj._singleton_ready = False  # type: ignore[attr-defined]
            return obj

    def __init__(self, db_path: str | None = None) -> None:
        if getattr(self, "_singleton_ready", False):
            return
        self.db_path = resolve_app_settings_db_path(db_path)
        self._cache: dict[str, Any] | None = None
        self._cache_lock = threading.Lock()
        self._ensure_schema()
        self._singleton_ready = True

    @classmethod
    def clear_shared_for_tests(cls) -> None:
        with cls._shared_lock:
            cls._shared.clear()

    def _connect(self) -> sqlite3.Connection:
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
        with self._cache_lock:
            self._cache = None

    def get_all(self) -> dict[str, Any]:
        """Load all settings in one connection (cached until the next set)."""
        with self._cache_lock:
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

        with self._cache_lock:
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
