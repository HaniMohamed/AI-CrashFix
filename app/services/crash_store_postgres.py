from __future__ import annotations

import json
import os
from datetime import datetime
from typing import Any

import psycopg
from psycopg.rows import dict_row
from psycopg.types.json import Json

from app.config import AI_CRASH_FIX_CRASH_DB_URL, BQ_PROJECT_ID
from app.services.crash_store_common import (
    PIPELINE_FLAG_COLUMNS,
    recompute_pipeline_complete,
    row_to_dict,
)

_ALL_COLUMNS = (
    "crash_id",
    "jira_issue_id",
    "pr_url",
    "status",
    "created_at",
    "updated_at",
    *PIPELINE_FLAG_COLUMNS,
)

_SCHEMA_SQL = """
CREATE TABLE IF NOT EXISTS crashes (
  firebase_project_id TEXT NOT NULL,
  crash_id TEXT NOT NULL,
  jira_issue_id TEXT,
  pr_url TEXT,
  status TEXT NOT NULL DEFAULT 'in_progress',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  result JSONB,
  analysis_done BOOLEAN NOT NULL DEFAULT FALSE,
  jira_created BOOLEAN NOT NULL DEFAULT FALSE,
  fix_generated BOOLEAN NOT NULL DEFAULT FALSE,
  fix_validated BOOLEAN NOT NULL DEFAULT FALSE,
  diff_applied BOOLEAN NOT NULL DEFAULT FALSE,
  branch_created BOOLEAN NOT NULL DEFAULT FALSE,
  mr_created BOOLEAN NOT NULL DEFAULT FALSE,
  pipeline_complete BOOLEAN NOT NULL DEFAULT FALSE,
  PRIMARY KEY (firebase_project_id, crash_id)
);
CREATE INDEX IF NOT EXISTS idx_crashes_project_updated
  ON crashes (firebase_project_id, updated_at DESC);
"""

_schema_ready = False


def _crash_db_url() -> str:
    url = (AI_CRASH_FIX_CRASH_DB_URL or "").strip()
    if not url:
        raise ValueError(
            "AI_CRASH_FIX_CRASH_DB_URL is required when AI_CRASH_FIX_CRASH_STORE_BACKEND=postgres"
        )
    return url


def ensure_postgres_schema(conn: psycopg.Connection) -> None:
    global _schema_ready
    if _schema_ready:
        return
    with conn.cursor() as cur:
        for statement in (part.strip() for part in _SCHEMA_SQL.split(";")):
            if statement:
                cur.execute(statement)
    conn.commit()
    _schema_ready = True


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
            ensure_postgres_schema(conn)

    def _connect(self) -> psycopg.Connection:
        return psycopg.connect(self.db_path, row_factory=dict_row)

    def insert_crash(self, crash_id: str) -> None:
        now = datetime.utcnow()
        with self._connect() as conn:
            with conn.cursor() as cur:
                cur.execute(
                    """
                    INSERT INTO crashes (firebase_project_id, crash_id, created_at, updated_at, status)
                    VALUES (%s, %s, %s, %s, 'in_progress')
                    ON CONFLICT (firebase_project_id, crash_id) DO NOTHING
                    """,
                    (self.project_id, crash_id, now, now),
                )
            conn.commit()

    def update_result(self, crash_id: str, result: dict) -> None:
        now = datetime.utcnow()
        with self._connect() as conn:
            with conn.cursor() as cur:
                if result.get("graph_error"):
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

        now = datetime.utcnow()
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
