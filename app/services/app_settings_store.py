from __future__ import annotations

import json
import os
import sqlite3
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Any


def _data_dir() -> Path | None:
    raw = (os.environ.get("AI_CRASH_FIX_DATA_DIR") or "").strip()
    if not raw:
        return None
    try:
        return Path(raw).expanduser().resolve()
    except Exception:
        return None


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
    """

    def __init__(self, db_path: str | None = None) -> None:
        path = (db_path or os.environ.get("AI_CRASH_FIX_REPO_REGISTRY_DB") or "").strip()
        if not path:
            base = _data_dir()
            if base is not None:
                path = os.fspath((base / "db" / "repo_registry.db").resolve())
            else:
                path = "db/repo_registry.db"
        p = Path(path).expanduser().resolve()
        p.parent.mkdir(parents=True, exist_ok=True)
        self.db_path = str(p)
        self._ensure_schema()

    def _connect(self) -> sqlite3.Connection:
        return sqlite3.connect(self.db_path, timeout=30.0)

    def _ensure_schema(self) -> None:
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

    def get(self, *, k: str) -> Any | None:
        key = (k or "").strip()
        if not key:
            return None
        with self._connect() as conn:
            row = conn.execute(
                "SELECT v FROM app_settings WHERE k = ?",
                (key,),
            ).fetchone()
        if not row:
            return None
        raw = row[0]
        if raw is None:
            return None
        try:
            return json.loads(str(raw))
        except Exception:
            return None

    def get_updated_at(self) -> str | None:
        with self._connect() as conn:
            row = conn.execute(
                "SELECT updated_at FROM app_settings ORDER BY datetime(updated_at) DESC LIMIT 1"
            ).fetchone()
        if not row:
            return None
        v = row[0]
        return str(v).strip() or None

