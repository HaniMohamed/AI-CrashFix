from __future__ import annotations

import os
from typing import Protocol

from app.config import AI_CRASH_FIX_CRASH_STORE_BACKEND
from app.services.crash_store_postgres import PostgresCrashStore, check_postgres_crash_store
from app.services.crash_store_sqlite import SqliteCrashStore


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


def crash_store_health() -> dict[str, object]:
    """Health payload for ``GET /api/health`` crash_store section."""
    try:
        backend = crash_store_backend_name()
    except ValueError as exc:
        return {"backend": "unknown", "ok": False, "error": str(exc)}

    if backend == "postgres":
        ok, error = check_postgres_crash_store()
        return {"backend": backend, "ok": ok, "error": error}

    return {"backend": backend, "ok": True, "error": None}


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
