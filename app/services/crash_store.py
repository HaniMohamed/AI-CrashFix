import json
import sqlite3
from datetime import datetime
from pathlib import Path

from app.config import BQ_PROJECT_ID

# Persisted as 0/1 in SQLite
_PIPELINE_FLAG_COLUMNS = (
    "analysis_done",
    "jira_created",
    "fix_generated",
    "fix_validated",
    "diff_applied",
    "branch_created",
    "mr_created",
    "pipeline_complete",
)


class CrashStore:
    """SQLite-backed progress for each crash through the fix pipeline.

    Connections are **not** kept open on ``self``: every operation uses a
    short-lived ``sqlite3.connect(self.db_path)`` in the **calling thread**.
    That keeps the store safe when the LangGraph pipeline runs on a worker
    thread (e.g. ``POST /api/runs``) while HTTP handlers or imports created
    ``CrashStore()`` on another thread.
    """

    def __init__(self, db_path=f"db/{BQ_PROJECT_ID}_crash_store.db"):
        path = Path(db_path).expanduser().resolve()
        path.parent.mkdir(parents=True, exist_ok=True)
        self.db_path = str(path)
        self._ensure_schema()

    def _connect(self) -> sqlite3.Connection:
        return sqlite3.connect(self.db_path, timeout=30.0)

    def _ensure_schema(self) -> None:
        with self._connect() as conn:
            self._create_table(conn)
            self._migrate_columns(conn)
            conn.commit()

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
            pipeline_complete INTEGER NOT NULL DEFAULT 0
        )
        """
        )

    def _migrate_columns(self, conn: sqlite3.Connection) -> None:
        cur = conn.execute("PRAGMA table_info(crashes)")
        existing = {row[1] for row in cur.fetchall()}
        for name in _PIPELINE_FLAG_COLUMNS:
            if name not in existing:
                conn.execute(
                    f"ALTER TABLE crashes ADD COLUMN {name} INTEGER NOT NULL DEFAULT 0"
                )

    def insert_crash(self, crash_id: str):
        """Ensure a row exists for this crash without clobbering existing progress."""
        now = datetime.utcnow().isoformat()
        with self._connect() as conn:
            conn.execute(
                """
        INSERT OR IGNORE INTO crashes (crash_id, created_at, updated_at, status)
        VALUES (?, ?, ?, 'in_progress')
        """,
                (crash_id, now, now),
            )
            conn.commit()

    def update_result(self, crash_id: str, result: dict):
        """Persist ``result`` JSON. If ``graph_error`` is set, row ``status`` becomes ``failed``."""
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
        """Set any subset of step flags and/or identifiers, then recompute pipeline_complete."""
        sets: list[str] = []
        vals: list[object] = []

        def add_bool(col: str, v: bool | None):
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
            self._recompute_pipeline_complete(conn, crash_id, now)
            conn.commit()

    def _recompute_pipeline_complete(
        self, conn: sqlite3.Connection, crash_id: str, now_iso: str | None = None
    ) -> None:
        """
        pipeline_complete when all required steps succeeded (Jira is optional).
        Required: analysis, fix generated, fix validated, diff applied, branch, MR.
        """
        now_iso = now_iso or datetime.utcnow().isoformat()
        row = conn.execute(
            f"""
            SELECT
              {", ".join(c for c in _PIPELINE_FLAG_COLUMNS if c != "pipeline_complete")},
              status
            FROM crashes WHERE crash_id = ?
            """,
            (crash_id,),
        ).fetchone()
        if not row:
            return
        (
            analysis_done,
            _jira_created,
            fix_generated,
            fix_validated,
            diff_applied,
            branch_created,
            mr_created,
            existing_status,
        ) = row
        complete = int(
            bool(analysis_done)
            and bool(fix_generated)
            and bool(fix_validated)
            and bool(diff_applied)
            and bool(branch_created)
            and bool(mr_created)
        )
        # Never overwrite a terminal failure back into in_progress while step flags change.
        status = "completed" if complete else ("failed" if str(existing_status or "").lower() == "failed" else "in_progress")
        conn.execute(
            """
            UPDATE crashes
            SET pipeline_complete = ?, status = ?, updated_at = ?
            WHERE crash_id = ?
            """,
            (complete, status, now_iso, crash_id),
        )

    def is_processed(self, crash_id: str) -> bool:
        """True when the full required pipeline finished (Jira not required)."""
        with self._connect() as conn:
            cursor = conn.execute(
                "SELECT pipeline_complete FROM crashes WHERE crash_id = ?",
                (crash_id,),
            )
            row = cursor.fetchone()
        return bool(row and row[0])

    # ---- Read-only helpers (used by the API layer) -----------------------------
    # These open a short-lived connection so they're safe to call from any thread.

    _ALL_COLUMNS = (
        "crash_id",
        "jira_issue_id",
        "pr_url",
        "status",
        "created_at",
        "updated_at",
        *_PIPELINE_FLAG_COLUMNS,
    )

    @classmethod
    def _row_to_dict(cls, row: sqlite3.Row, *, include_result: bool) -> dict:
        out = {k: row[k] for k in cls._ALL_COLUMNS if k in row.keys()}
        # Coerce 0/1 ints to bool for the boolean flag columns.
        for col in _PIPELINE_FLAG_COLUMNS:
            if col in out:
                out[col] = bool(out[col])
        if include_result and "result" in row.keys():
            raw = row["result"]
            if raw:
                try:
                    out["result"] = json.loads(raw)
                except Exception:
                    out["result"] = raw
            else:
                out["result"] = None
        return out

    def list_crashes(
        self,
        *,
        status: str | None = None,
        limit: int = 50,
        offset: int = 0,
        include_result: bool = False,
    ) -> list[dict]:
        """Return crash rows ordered by `updated_at` desc. Read-only."""
        cols = ", ".join(self._ALL_COLUMNS) + (", result" if include_result else "")
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
        return [self._row_to_dict(r, include_result=include_result) for r in rows]

    def get_crash(self, crash_id: str, *, include_result: bool = True) -> dict | None:
        """Return a single crash row (with parsed `result`), or None if missing."""
        cols = ", ".join(self._ALL_COLUMNS) + (", result" if include_result else "")
        with self._connect() as conn:
            conn.row_factory = sqlite3.Row
            row = conn.execute(
                f"SELECT {cols} FROM crashes WHERE crash_id = ?",
                (crash_id,),
            ).fetchone()
        if row is None:
            return None
        return self._row_to_dict(row, include_result=include_result)

    def iter_all_results(self):
        """Yield `(row_dict, parsed_result_or_none)` for every crash.

        Used by the analytics aggregator. Streams rows so memory stays bounded
        even when the store grows.
        """
        cols = ", ".join(self._ALL_COLUMNS) + ", result"
        with self._connect() as conn:
            conn.row_factory = sqlite3.Row
            cursor = conn.execute(f"SELECT {cols} FROM crashes")
            for row in cursor:
                row_dict = self._row_to_dict(row, include_result=False)
                raw = row["result"] if "result" in row.keys() else None
                parsed: dict | None = None
                if raw:
                    try:
                        parsed = json.loads(raw)
                    except Exception:
                        parsed = None
                yield row_dict, parsed
