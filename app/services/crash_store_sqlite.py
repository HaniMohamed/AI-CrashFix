from __future__ import annotations

import json
import os
import sqlite3
import sys
from datetime import datetime
from pathlib import Path

from app.config import BQ_PROJECT_ID
from app.services.crash_store_common import (
    FEEDBACK_COLUMNS,
    PIPELINE_FLAG_COLUMNS,
    row_to_dict,
    recompute_pipeline_complete,
)
from app.services.sqlite_util import (
    connect_sqlite,
    mark_schema_ensured,
    schema_needs_ensure,
)
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


class SqliteCrashStore:
    """SQLite-backed progress for each crash through the fix pipeline."""

    backend = "sqlite"

    def __init__(
        self,
        db_path: str | None = None,
        *,
        repo_key: str | None = None,
        project_id: str | None = None,
    ):
        env_db = (os.environ.get("AI_CRASH_FIX_DB_PATH") or "").strip() or None
        repo_key = (repo_key or "").strip() or None
        project_id = (project_id or "").strip() or None
        resolved_project = project_id or (BQ_PROJECT_ID or "").strip() or "default"
        self.project_id = resolved_project

        if db_path:
            resolved = db_path
        elif env_db:
            resolved = env_db
        elif repo_key:
            resolved = f"db/{resolved_project}_{repo_key}_crash_store.db"
        else:
            resolved = None
        if not resolved:
            if sys.platform == "darwin" and bool(getattr(sys, "frozen", False)):
                resolved = str(
                    (
                        __import__("app.brand", fromlist=["resolve_macos_application_support"])
                        .resolve_macos_application_support()
                        / f"{resolved_project}_crash_store.db"
                    )
                )
            else:
                resolved = f"db/{resolved_project}_crash_store.db"

        data_dir = (os.environ.get("AI_CRASH_FIX_DATA_DIR") or "").strip()
        if data_dir:
            try:
                base = Path(data_dir).expanduser().resolve()
                rp = Path(resolved)
                if not rp.is_absolute():
                    resolved = os.fspath((base / rp).resolve())
            except Exception:
                pass

        path = Path(resolved).expanduser().resolve()
        path.parent.mkdir(parents=True, exist_ok=True)
        self.db_path = str(path)
        self.store_key = self.db_path
        self._ensure_schema()

    def _connect(self):
        return connect_sqlite(self.db_path)

    def _ensure_schema(self) -> None:
        if not schema_needs_ensure(f"crash_store:{self.db_path}"):
            return
        with self._connect() as conn:
            self._create_table(conn)
            self._migrate_columns(conn)
            conn.commit()
        mark_schema_ensured(f"crash_store:{self.db_path}")

    def _create_table(self, conn: sqlite3.Connection) -> None:
        conn.execute(
            """
        CREATE TABLE IF NOT EXISTS crashes (
            crash_id TEXT PRIMARY KEY,
            jira_issue_id TEXT,
            pr_url TEXT,
            status TEXT DEFAULT 'in_progress',
            created_at TEXT DEFAULT CURRENT_TIMESTAMP,
            updated_at TEXT DEFAULT CURRENT_TIMESTAMP,
            result TEXT DEFAULT NULL,
            analysis_done INTEGER NOT NULL DEFAULT 0,
            jira_created INTEGER NOT NULL DEFAULT 0,
            fix_generated INTEGER NOT NULL DEFAULT 0,
            fix_validated INTEGER NOT NULL DEFAULT 0,
            diff_applied INTEGER NOT NULL DEFAULT 0,
            branch_created INTEGER NOT NULL DEFAULT 0,
            mr_created INTEGER NOT NULL DEFAULT 0,
            pipeline_complete INTEGER NOT NULL DEFAULT 0,
            feedback_iteration_count INTEGER NOT NULL DEFAULT 0,
            feedback_locked INTEGER NOT NULL DEFAULT 0,
            restart_count INTEGER NOT NULL DEFAULT 0
        )
        """
        )
        conn.execute(
            """
        CREATE TABLE IF NOT EXISTS crash_feedback (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            crash_id TEXT NOT NULL,
            role TEXT NOT NULL,
            message TEXT NOT NULL,
            status TEXT,
            iteration INTEGER NOT NULL DEFAULT 0,
            created_at TEXT DEFAULT CURRENT_TIMESTAMP
        )
        """
        )

    def _migrate_columns(self, conn: sqlite3.Connection) -> None:
        cur = conn.execute("PRAGMA table_info(crashes)")
        existing = {row[1] for row in cur.fetchall()}
        for name in PIPELINE_FLAG_COLUMNS:
            if name not in existing:
                conn.execute(
                    f"ALTER TABLE crashes ADD COLUMN {name} INTEGER NOT NULL DEFAULT 0"
                )
        if "created_by_user_id" not in existing:
            conn.execute("ALTER TABLE crashes ADD COLUMN created_by_user_id TEXT")
        if "feedback_iteration_count" not in existing:
            conn.execute(
                "ALTER TABLE crashes ADD COLUMN feedback_iteration_count INTEGER NOT NULL DEFAULT 0"
            )
        if "feedback_locked" not in existing:
            conn.execute(
                "ALTER TABLE crashes ADD COLUMN feedback_locked INTEGER NOT NULL DEFAULT 0"
            )
        if "restart_count" not in existing:
            conn.execute(
                "ALTER TABLE crashes ADD COLUMN restart_count INTEGER NOT NULL DEFAULT 0"
            )

    def insert_crash(self, crash_id: str) -> None:
        now = datetime.utcnow().isoformat()
        created_by = resolve_user_id(required=False)
        with self._connect() as conn:
            conn.execute(
                """
        INSERT OR IGNORE INTO crashes (crash_id, created_at, updated_at, status, created_by_user_id)
        VALUES (?, ?, ?, 'in_progress', ?)
        """,
                (crash_id, now, now, created_by),
            )
            conn.commit()

    def update_result(self, crash_id: str, result: dict) -> None:
        now = datetime.utcnow().isoformat()
        payload = json.dumps(result)
        with self._connect() as conn:
            if result.get("graph_error"):
                conn.execute(
                    """
                    UPDATE crashes
                    SET result = ?, updated_at = ?, status = 'failed'
                    WHERE crash_id = ?
                    """,
                    (payload, now, crash_id),
                )
            elif str(result.get("pipeline_status") or "").lower() == "skipped":
                conn.execute(
                    """
                    UPDATE crashes
                    SET result = ?, updated_at = ?, status = 'skipped'
                    WHERE crash_id = ?
                    """,
                    (payload, now, crash_id),
                )
            else:
                conn.execute(
                    """
                    UPDATE crashes SET result = ?, updated_at = ? WHERE crash_id = ?
                    """,
                    (payload, now, crash_id),
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
        vals: list[object] = []

        def add_bool(col: str, v: bool | None) -> None:
            if v is None:
                return
            sets.append(f"{col} = ?")
            vals.append(1 if v else 0)

        add_bool("analysis_done", analysis_done)
        add_bool("jira_created", jira_created)
        add_bool("fix_generated", fix_generated)
        add_bool("fix_validated", fix_validated)
        add_bool("diff_applied", diff_applied)
        add_bool("branch_created", branch_created)
        add_bool("mr_created", mr_created)

        if jira_issue_id is not None:
            sets.append("jira_issue_id = ?")
            vals.append(jira_issue_id)
        if pr_url is not None:
            sets.append("pr_url = ?")
            vals.append(pr_url)

        now = datetime.utcnow().isoformat()
        with self._connect() as conn:
            if sets:
                sets.append("updated_at = ?")
                vals.append(now)
                vals.append(crash_id)
                conn.execute(
                    f"UPDATE crashes SET {', '.join(sets)} WHERE crash_id = ?",
                    vals,
                )
            recompute_pipeline_complete(conn, crash_id, now_iso=now, dialect="sqlite")
            conn.commit()

    def set_feedback_lock(self, crash_id: str, locked: bool) -> None:
        now = datetime.utcnow().isoformat()
        with self._connect() as conn:
            conn.execute(
                "UPDATE crashes SET feedback_locked = ?, updated_at = ? WHERE crash_id = ?",
                (1 if locked else 0, now, crash_id),
            )
            conn.commit()

    def bump_feedback_iteration(self, crash_id: str) -> int:
        now = datetime.utcnow().isoformat()
        with self._connect() as conn:
            conn.execute(
                """
                UPDATE crashes
                SET feedback_iteration_count = feedback_iteration_count + 1, updated_at = ?
                WHERE crash_id = ?
                """,
                (now, crash_id),
            )
            row = conn.execute(
                "SELECT feedback_iteration_count FROM crashes WHERE crash_id = ?",
                (crash_id,),
            ).fetchone()
            conn.commit()
        return int(row[0]) if row else 0

    def bump_restart_count(self, crash_id: str) -> int:
        now = datetime.utcnow().isoformat()
        with self._connect() as conn:
            conn.execute(
                """
                UPDATE crashes
                SET restart_count = restart_count + 1, updated_at = ?
                WHERE crash_id = ?
                """,
                (now, crash_id),
            )
            row = conn.execute(
                "SELECT restart_count FROM crashes WHERE crash_id = ?",
                (crash_id,),
            ).fetchone()
            conn.commit()
        return int(row[0]) if row else 0

    def is_processed(self, crash_id: str) -> bool:
        with self._connect() as conn:
            cursor = conn.execute(
                "SELECT pipeline_complete FROM crashes WHERE crash_id = ?",
                (crash_id,),
            )
            row = cursor.fetchone()
        return bool(row and row[0])

    def list_crashes(
        self,
        *,
        status: str | None = None,
        limit: int = 50,
        offset: int = 0,
        include_result: bool = False,
    ) -> list[dict]:
        cols = ", ".join(_ALL_COLUMNS) + (", result" if include_result else "")
        sql = f"SELECT {cols} FROM crashes"
        params: list[object] = []
        if status:
            sql += " WHERE status = ?"
            params.append(status)
        sql += " ORDER BY datetime(updated_at) DESC LIMIT ? OFFSET ?"
        params.extend([int(limit), int(offset)])

        with self._connect() as conn:
            conn.row_factory = sqlite3.Row
            rows = conn.execute(sql, params).fetchall()
        return [row_to_dict(r, include_result=include_result) for r in rows]

    def get_crash(self, crash_id: str, *, include_result: bool = True) -> dict | None:
        cols = ", ".join(_ALL_COLUMNS) + (", result" if include_result else "")
        with self._connect() as conn:
            conn.row_factory = sqlite3.Row
            row = conn.execute(
                f"SELECT {cols} FROM crashes WHERE crash_id = ?",
                (crash_id,),
            ).fetchone()
        if row is None:
            return None
        return row_to_dict(row, include_result=include_result)

    def iter_all_results(self):
        cols = ", ".join(_ALL_COLUMNS) + ", result"
        rows_out: list[tuple[dict, dict | None]] = []
        with self._connect() as conn:
            conn.row_factory = sqlite3.Row
            cursor = conn.execute(f"SELECT {cols} FROM crashes")
            for row in cursor:
                row_dict = row_to_dict(row, include_result=False)
                raw = row["result"] if "result" in row.keys() else None
                parsed: dict | None = None
                if raw:
                    try:
                        parsed = json.loads(raw)
                    except Exception:
                        parsed = None
                rows_out.append((row_dict, parsed))
        yield from rows_out
