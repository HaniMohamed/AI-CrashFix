from __future__ import annotations

import logging
import os
import time
from typing import Protocol

from app.config import AI_CRASH_FIX_CRASH_STORE_BACKEND
from app.services.crash_store_postgres import PostgresCrashStore, check_postgres_crash_store
from app.services.crash_store_sqlite import SqliteCrashStore

_log = logging.getLogger(__name__)

# Set by ensure_crash_store_available() when Postgres is unreachable.
_CRASH_STORE_FALLBACK: dict[str, object] | None = None


class CrashStoreBackend(Protocol):
    backend: str
    project_id: str
    store_key: str
    db_path: str

    def insert_crash(self, crash_id: str) -> None: ...

    def update_result(self, crash_id: str, result: dict) -> None: ...

    def set_pipeline_flags(
        self,
        crash_id: str,
        *,
        analysis_done: bool | None = None,
        jira_created: bool | None = None,
        fix_generated: bool | None = None,
        fix_validated: bool | None = None,
        diff_applied: bool | None = None,
        branch_created: bool | None = None,
        mr_created: bool | None = None,
        jira_issue_id: str | None = None,
        pr_url: str | None = None,
    ) -> None: ...

    def is_processed(self, crash_id: str) -> bool: ...

    def set_feedback_lock(self, crash_id: str, locked: bool) -> None: ...

    def bump_feedback_iteration(self, crash_id: str) -> int: ...

    def bump_restart_count(self, crash_id: str) -> int: ...

    def list_crashes(
        self,
        *,
        status: str | None = None,
        limit: int = 50,
        offset: int = 0,
        include_result: bool = False,
    ) -> list[dict]: ...

    def get_crash(self, crash_id: str, *, include_result: bool = True) -> dict | None: ...

    def iter_all_results(self): ...


def crash_store_backend_name() -> str:
    raw = (os.getenv("AI_CRASH_FIX_CRASH_STORE_BACKEND") or AI_CRASH_FIX_CRASH_STORE_BACKEND or "sqlite")
    backend = raw.strip().lower()
    if backend not in {"sqlite", "postgres"}:
        raise ValueError(
            f"Invalid AI_CRASH_FIX_CRASH_STORE_BACKEND={raw!r}; expected 'sqlite' or 'postgres'"
        )
    return backend


def uses_postgres_crash_store() -> bool:
    return crash_store_backend_name() == "postgres"


def _crash_store_strict() -> bool:
    return (os.getenv("AI_CRASH_FIX_CRASH_STORE_STRICT") or "").strip() == "1"


def _sync_crash_store_config_from_environ() -> None:
    """Keep ``app.config`` module attrs aligned with live process env."""
    import app.config as cfg

    cfg.AI_CRASH_FIX_CRASH_STORE_BACKEND = (
        (os.getenv("AI_CRASH_FIX_CRASH_STORE_BACKEND") or "sqlite").strip().lower()
        or "sqlite"
    )
    cfg.AI_CRASH_FIX_CRASH_DB_URL = (
        (os.getenv("AI_CRASH_FIX_CRASH_DB_URL") or "").strip() or None
    )


def ensure_crash_store_available() -> dict[str, object]:
    """If Postgres is configured but unreachable, fall back to local SQLite.

    Team launch env files often pin ``AI_CRASH_FIX_CRASH_STORE_BACKEND=postgres``.
    When that host is down (VPN off, Docker stopped), Fixora would otherwise hard-block
    the UI. Falling back keeps LLM/settings from the same env file while using a
    local crash store.

    Set ``AI_CRASH_FIX_CRASH_STORE_STRICT=1`` to keep the hard failure instead.
    """
    global _CRASH_STORE_FALLBACK, _CRASH_STORE_HEALTH_CACHE, _CRASH_STORE_HEALTH_CACHED_AT

    _sync_crash_store_config_from_environ()
    _CRASH_STORE_FALLBACK = None

    try:
        backend = crash_store_backend_name()
    except ValueError as exc:
        return {"backend": "unknown", "ok": False, "error": str(exc)}

    if backend != "postgres":
        return {"backend": backend, "ok": True, "error": None}

    ok, error = check_postgres_crash_store()
    if ok:
        return {"backend": "postgres", "ok": True, "error": None}

    if _crash_store_strict():
        return {"backend": "postgres", "ok": False, "error": error}

    _log.warning(
        "Postgres crash store unreachable (%s); falling back to local SQLite for this session",
        error,
    )
    os.environ["AI_CRASH_FIX_CRASH_STORE_BACKEND"] = "sqlite"
    _sync_crash_store_config_from_environ()
    _CRASH_STORE_FALLBACK = {
        "from": "postgres",
        "to": "sqlite",
        "error": error,
    }
    # Drop facades that may already be bound to Postgres (auth/settings/repos).
    try:
        from app.services.store_bootstrap import reset_store_singletons

        reset_store_singletons()
    except Exception:
        _log.warning("Failed to reset store singletons after Postgres fallback", exc_info=True)
    # Force next health() call to re-read backend=sqlite.
    _CRASH_STORE_HEALTH_CACHE = None
    _CRASH_STORE_HEALTH_CACHED_AT = 0.0
    return {
        "backend": "sqlite",
        "ok": True,
        "error": None,
        "fallback_from": "postgres",
        "fallback_reason": error,
    }


_CRASH_STORE_HEALTH_CACHE: dict[str, object] | None = None
_CRASH_STORE_HEALTH_CACHED_AT = 0.0
_CRASH_STORE_HEALTH_TTL_SEC = 10.0


def crash_store_health(*, force: bool = False) -> dict[str, object]:
    """Health payload for ``GET /api/health`` crash_store section.

    Caches Postgres probes briefly so a transient blip does not flap the UI
    every 15s health poll, and so we do not open a new DB connection each time.
    """
    global _CRASH_STORE_HEALTH_CACHE, _CRASH_STORE_HEALTH_CACHED_AT

    now = time.monotonic()
    if (
        not force
        and _CRASH_STORE_HEALTH_CACHE is not None
        and (now - _CRASH_STORE_HEALTH_CACHED_AT) < _CRASH_STORE_HEALTH_TTL_SEC
    ):
        return dict(_CRASH_STORE_HEALTH_CACHE)

    try:
        backend = crash_store_backend_name()
    except ValueError as exc:
        payload: dict[str, object] = {"backend": "unknown", "ok": False, "error": str(exc)}
        _CRASH_STORE_HEALTH_CACHE = payload
        _CRASH_STORE_HEALTH_CACHED_AT = now
        return dict(payload)

    if backend == "postgres":
        ok, error = check_postgres_crash_store()
        payload = {"backend": backend, "ok": ok, "error": error}
    else:
        payload = {"backend": backend, "ok": True, "error": None}
        if _CRASH_STORE_FALLBACK:
            payload["fallback_from"] = _CRASH_STORE_FALLBACK.get("from")
            payload["fallback_reason"] = _CRASH_STORE_FALLBACK.get("error")

    _CRASH_STORE_HEALTH_CACHE = payload
    _CRASH_STORE_HEALTH_CACHED_AT = now
    return dict(payload)


def open_crash_store(
    db_path: str | None = None,
    *,
    repo_key: str | None = None,
    project_id: str | None = None,
) -> CrashStoreBackend:
    if uses_postgres_crash_store():
        return PostgresCrashStore(project_id=project_id)
    return SqliteCrashStore(db_path=db_path, repo_key=repo_key, project_id=project_id)


class CrashStore:
    """Crash pipeline store (SQLite local files or shared Postgres)."""

    def __init__(
        self,
        db_path: str | None = None,
        *,
        repo_key: str | None = None,
        project_id: str | None = None,
    ):
        self._impl = open_crash_store(
            db_path,
            repo_key=repo_key,
            project_id=project_id,
        )
        self.backend = self._impl.backend
        self.project_id = self._impl.project_id
        self.store_key = self._impl.store_key
        self.db_path = self._impl.db_path

    def insert_crash(self, crash_id: str) -> None:
        self._impl.insert_crash(crash_id)

    def update_result(self, crash_id: str, result: dict) -> None:
        self._impl.update_result(crash_id, result)

    def set_pipeline_flags(
        self,
        crash_id: str,
        *,
        analysis_done: bool | None = None,
        jira_created: bool | None = None,
        fix_generated: bool | None = None,
        fix_validated: bool | None = None,
        diff_applied: bool | None = None,
        branch_created: bool | None = None,
        mr_created: bool | None = None,
        jira_issue_id: str | None = None,
        pr_url: str | None = None,
    ) -> None:
        self._impl.set_pipeline_flags(
            crash_id,
            analysis_done=analysis_done,
            jira_created=jira_created,
            fix_generated=fix_generated,
            fix_validated=fix_validated,
            diff_applied=diff_applied,
            branch_created=branch_created,
            mr_created=mr_created,
            jira_issue_id=jira_issue_id,
            pr_url=pr_url,
        )

    def is_processed(self, crash_id: str) -> bool:
        return self._impl.is_processed(crash_id)

    def set_feedback_lock(self, crash_id: str, locked: bool) -> None:
        self._impl.set_feedback_lock(crash_id, locked)

    def bump_feedback_iteration(self, crash_id: str) -> int:
        return self._impl.bump_feedback_iteration(crash_id)

    def bump_restart_count(self, crash_id: str) -> int:
        return self._impl.bump_restart_count(crash_id)

    def list_crashes(
        self,
        *,
        status: str | None = None,
        limit: int = 50,
        offset: int = 0,
        include_result: bool = False,
    ) -> list[dict]:
        return self._impl.list_crashes(
            status=status,
            limit=limit,
            offset=offset,
            include_result=include_result,
        )

    def get_crash(self, crash_id: str, *, include_result: bool = True) -> dict | None:
        return self._impl.get_crash(crash_id, include_result=include_result)

    def iter_all_results(self):
        yield from self._impl.iter_all_results()
