from __future__ import annotations

import logging
import os
import threading
from dataclasses import dataclass
from pathlib import Path
from typing import Any, ClassVar


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
        if base is None:
            # Desktop bundles often run with cwd=/; never fall back to relative db/.
            try:
                import sys

                if sys.platform == "darwin":
                    from app.brand import resolve_macos_application_support

                    base = resolve_macos_application_support()
            except Exception:
                base = None
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


def _singleton_key(db_path: str | None = None) -> str:
    from app.services.crash_store import uses_postgres_crash_store
    from app.services.user_context import resolve_user_id

    if uses_postgres_crash_store():
        user_id = resolve_user_id(required=True)
        return f"postgres:{user_id}"
    return f"sqlite:{resolve_app_settings_db_path(db_path)}"


def _force_sqlite_backend_after_postgres_failure(exc: BaseException) -> None:
    from app.services.crash_store import _sync_crash_store_config_from_environ

    logging.getLogger(__name__).warning(
        "Postgres app settings store unavailable (%s); using local SQLite",
        exc,
    )
    os.environ["AI_CRASH_FIX_CRASH_STORE_BACKEND"] = "sqlite"
    _sync_crash_store_config_from_environ()


class AppSettingsStore:
    """
    Settings facade (SQLite local or shared Postgres per user).

    Secrets are stored but never returned by API layers.
    """

    _shared: ClassVar[dict[str, AppSettingsStore]] = {}
    _shared_lock: ClassVar[threading.Lock] = threading.Lock()

    def __new__(cls, db_path: str | None = None) -> AppSettingsStore:
        key = _singleton_key(db_path)
        with cls._shared_lock:
            existing = cls._shared.get(key)
            if existing is not None:
                return existing
            obj = super().__new__(cls)
            cls._shared[key] = obj
            obj._singleton_ready = False  # type: ignore[attr-defined]
            obj._singleton_key = key  # type: ignore[attr-defined]
            return obj

    def __init__(self, db_path: str | None = None) -> None:
        if getattr(self, "_singleton_ready", False):
            return
        from app.services.crash_store import uses_postgres_crash_store

        try:
            if uses_postgres_crash_store():
                try:
                    from app.services.app_settings_postgres import PostgresAppSettingsStore

                    self._impl = PostgresAppSettingsStore()
                except Exception as exc:
                    _force_sqlite_backend_after_postgres_failure(exc)
                    with type(self)._shared_lock:
                        old = getattr(self, "_singleton_key", None)
                        if old and type(self)._shared.get(old) is self:
                            del type(self)._shared[old]
                        new_key = _singleton_key(db_path)
                        type(self)._shared[new_key] = self
                        self._singleton_key = new_key  # type: ignore[attr-defined]
                    from app.services.app_settings_sqlite import SqliteAppSettingsStore

                    self._impl = SqliteAppSettingsStore(db_path=db_path)
            else:
                from app.services.app_settings_sqlite import SqliteAppSettingsStore

                self._impl = SqliteAppSettingsStore(db_path=db_path)
            self.db_path = self._impl.db_path
            self._singleton_ready = True
        except Exception:
            with type(self)._shared_lock:
                key = getattr(self, "_singleton_key", None)
                if key and type(self)._shared.get(key) is self:
                    del type(self)._shared[key]
            raise

    @classmethod
    def clear_shared_for_tests(cls) -> None:
        with cls._shared_lock:
            cls._shared.clear()

    def get_all(self) -> dict[str, Any]:
        return self._impl.get_all()

    def set(self, *, k: str, v: Any) -> None:
        self._impl.set(k=k, v=v)

    def get(self, *, k: str) -> Any | None:
        return self._impl.get(k=k)

    def get_updated_at(self) -> str | None:
        return self._impl.get_updated_at()
