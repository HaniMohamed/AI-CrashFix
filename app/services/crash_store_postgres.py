from __future__ import annotations

import json
import os
from datetime import datetime, timezone
from typing import Any

import psycopg
from psycopg.rows import dict_row
from psycopg.types.json import Json

from app.config import AI_CRASH_FIX_CRASH_DB_URL, BQ_PROJECT_ID
from app.services.crash_store_common import (
    FEEDBACK_COLUMNS,
    PIPELINE_FLAG_COLUMNS,
    recompute_pipeline_complete,
    row_to_dict,
)
from app.services.postgres_schema import connect_postgres, ensure_app_postgres_schema
from app.services.user_context import resolve_user_id

_ALL_COLUMNS = (
    "crash_id",
    "jira_issue_id",
    "pr_url",
    "status",
    "created_at",
    "updated_at",
    "created_by_user_id",
    *PIPELINE_FLAG_COLUMNS,
    *FEEDBACK_COLUMNS,
)


def _crash_db_url() -> str:
    # Prefer live process env (launch .env applied at startup) over import-time config.
    url = (
        (os.getenv("AI_CRASH_FIX_CRASH_DB_URL") or "").strip()
        or (AI_CRASH_FIX_CRASH_DB_URL or "").strip()
    )
    if not url:
        raise ValueError(
            "AI_CRASH_FIX_CRASH_DB_URL is required when AI_CRASH_FIX_CRASH_STORE_BACKEND=postgres"
        )
    return url


def ensure_postgres_schema(conn: psycopg.Connection) -> None:
    """Compatibility wrapper; prefer :func:`ensure_app_postgres_schema`."""
    ensure_app_postgres_schema(conn)


def check_postgres_crash_store(*, connect_timeout: int = 3) -> tuple[bool, str | None]:
    """Return (ok, error_message) for the configured Postgres crash store."""
    try:
        url = _crash_db_url()
    except ValueError as exc:
        return False, str(exc)
    try:
        with connect_postgres(url, connect_timeout=connect_timeout) as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT 1")
    except Exception as exc:
        return False, str(exc)
    return True, None


class PostgresCrashStore:
    """Postgres-backed crash pipeline store scoped by firebase project id."""

    backend = "postgres"

    def __init__(
        self,
        db_path: str | None = None,
        *,
        repo_key: str | None = None,
        project_id: str | None = None,
    ) -> None:
        del db_path, repo_key
        resolved_project = (project_id or "").strip() or (BQ_PROJECT_ID or "").strip() or "default"
        self.project_id = resolved_project
        self.db_path = _crash_db_url()
        self.store_key = f"postgres:{self.project_id}"
        with self._connect() as conn:
            ensure_app_postgres_schema(conn)

    def _connect(self) -> psycopg.Connection:
        return connect_postgres(self.db_path, row_factory=dict_row)

    def insert_crash(self, crash_id: str) -> None:
        now = datetime.now(timezone.utc)
        created_by = resolve_user_id(required=False)
        with self._connect() as conn:
            with conn.cursor() as cur:
                cur.execute(
                    """
                    INSERT INTO crashes (
                      firebase_project_id, crash_id, created_at, updated_at, status, created_by_user_id
                    )
                    VALUES (%s, %s, %s, %s, 'in_progress', %s)
                    ON CONFLICT (firebase_project_id, crash_id) DO NOTHING
                    """,
                    (self.project_id, crash_id, now, now, created_by),
                )
            conn.commit()

    def update_result(self, crash_id: str, result: dict) -> None:
        now = datetime.now(timezone.utc)
        with self._connect() as conn:
            with conn.cursor() as cur:
                if result.get("graph_error") or result.get("pr_error"):
                    cur.execute(
                        """
                        UPDATE crashes
                        SET result = %s, updated_at = %s, status = 'failed'
                        WHERE firebase_project_id = %s AND crash_id = %s
                        """,
                        (Json(result), now, self.project_id, crash_id),
                    )
                elif str(result.get("pipeline_status") or "").lower() == "skipped":
                    cur.execute(
                        """
                        UPDATE crashes
                        SET result = %s, updated_at = %s, status = 'skipped'
                        WHERE firebase_project_id = %s AND crash_id = %s
                        """,
                        (Json(result), now, self.project_id, crash_id),
                    )
                else:
                    cur.execute(
                        """
                        UPDATE crashes
                        SET result = %s, updated_at = %s
                        WHERE firebase_project_id = %s AND crash_id = %s
                        """,
                        (Json(result), now, self.project_id, crash_id),
                    )
            conn.commit()

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
        sets: list[str] = []
        vals: list[Any] = []

        def add_bool(col: str, v: bool | None) -> None:
            if v is None:
                return
            sets.append(f"{col} = %s")
            vals.append(bool(v))

        add_bool("analysis_done", analysis_done)
        add_bool("jira_created", jira_created)
        add_bool("fix_generated", fix_generated)
        add_bool("fix_validated", fix_validated)
        add_bool("diff_applied", diff_applied)
        add_bool("branch_created", branch_created)
        add_bool("mr_created", mr_created)

        if jira_issue_id is not None:
            sets.append("jira_issue_id = %s")
            vals.append(jira_issue_id)
        if pr_url is not None:
            sets.append("pr_url = %s")
            vals.append(pr_url)

        now = datetime.now(timezone.utc)
        with self._connect() as conn:
            with conn.cursor() as cur:
                if sets:
                    sets.append("updated_at = %s")
                    vals.extend([now, self.project_id, crash_id])
                    cur.execute(
                        f"""
                        UPDATE crashes
                        SET {', '.join(sets)}
                        WHERE firebase_project_id = %s AND crash_id = %s
                        """,
                        vals,
                    )
                recompute_pipeline_complete(
                    cur,
                    crash_id,
                    now_iso=now.isoformat(),
                    dialect="postgres",
                    project_id=self.project_id,
                )
            conn.commit()

    def set_feedback_lock(self, crash_id: str, locked: bool) -> None:
        now = datetime.now(timezone.utc)
        with self._connect() as conn:
            with conn.cursor() as cur:
                cur.execute(
                    """
                    UPDATE crashes
                    SET feedback_locked = %s, updated_at = %s
                    WHERE firebase_project_id = %s AND crash_id = %s
                    """,
                    (bool(locked), now, self.project_id, crash_id),
                )
            conn.commit()

    def bump_feedback_iteration(self, crash_id: str) -> int:
        now = datetime.now(timezone.utc)
        with self._connect() as conn:
            with conn.cursor() as cur:
                cur.execute(
                    """
                    UPDATE crashes
                    SET feedback_iteration_count = feedback_iteration_count + 1, updated_at = %s
                    WHERE firebase_project_id = %s AND crash_id = %s
                    RETURNING feedback_iteration_count
                    """,
                    (now, self.project_id, crash_id),
                )
                row = cur.fetchone()
            conn.commit()
        return int(row["feedback_iteration_count"]) if row else 0

    def bump_restart_count(self, crash_id: str) -> int:
        now = datetime.now(timezone.utc)
        with self._connect() as conn:
            with conn.cursor() as cur:
                cur.execute(
                    """
                    UPDATE crashes
                    SET restart_count = restart_count + 1, updated_at = %s
                    WHERE firebase_project_id = %s AND crash_id = %s
                    RETURNING restart_count
                    """,
                    (now, self.project_id, crash_id),
                )
                row = cur.fetchone()
            conn.commit()
        return int(row["restart_count"]) if row else 0

    def is_processed(self, crash_id: str) -> bool:
        with self._connect() as conn:
            with conn.cursor() as cur:
                cur.execute(
                    """
                    SELECT pipeline_complete
                    FROM crashes
                    WHERE firebase_project_id = %s AND crash_id = %s
                    """,
                    (self.project_id, crash_id),
                )
                row = cur.fetchone()
        return bool(row and row.get("pipeline_complete"))

    def list_crashes(
        self,
        *,
        status: str | None = None,
        limit: int = 50,
        offset: int = 0,
        include_result: bool = False,
    ) -> list[dict]:
        cols = ", ".join(_ALL_COLUMNS) + (", result" if include_result else "")
        sql = f"""
            SELECT {cols}
            FROM crashes
            WHERE firebase_project_id = %s
            """
        params: list[Any] = [self.project_id]
        if status:
            sql += " AND status = %s"
            params.append(status)
        sql += " ORDER BY updated_at DESC LIMIT %s OFFSET %s"
        params.extend([int(limit), int(offset)])

        with self._connect() as conn:
            with conn.cursor() as cur:
                cur.execute(sql, params)
                rows = cur.fetchall()
        return [row_to_dict(r, include_result=include_result) for r in rows]

    def get_crash(self, crash_id: str, *, include_result: bool = True) -> dict | None:
        cols = ", ".join(_ALL_COLUMNS) + (", result" if include_result else "")
        with self._connect() as conn:
            with conn.cursor() as cur:
                cur.execute(
                    f"""
                    SELECT {cols}
                    FROM crashes
                    WHERE firebase_project_id = %s AND crash_id = %s
                    """,
                    (self.project_id, crash_id),
                )
                row = cur.fetchone()
        if row is None:
            return None
        return row_to_dict(row, include_result=include_result)

    def iter_all_results(self):
        cols = ", ".join(_ALL_COLUMNS) + ", result"
        with self._connect() as conn:
            with conn.cursor() as cur:
                cur.execute(
                    f"""
                    SELECT {cols}
                    FROM crashes
                    WHERE firebase_project_id = %s
                    """,
                    (self.project_id,),
                )
                for row in cur:
                    row_dict = row_to_dict(row, include_result=False)
                    raw = row.get("result")
                    parsed: dict | None = raw if isinstance(raw, dict) else None
                    if parsed is None and raw:
                        try:
                            parsed = json.loads(raw)
                        except Exception:
                            parsed = None
                    yield row_dict, parsed
