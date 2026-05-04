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
    """SQLite-backed progress for each crash through the fix pipeline."""

    def __init__(self, db_path=f"db/{BQ_PROJECT_ID}_crash_store.db"):
        Path(db_path).expanduser().resolve().parent.mkdir(parents=True, exist_ok=True)
        self.conn = sqlite3.connect(db_path)
        self._create_table()
        self._migrate_columns()

    def _create_table(self):
        self.conn.execute(
            """
        CREATE TABLE IF NOT EXISTS crashes (
            crash_id TEXT PRIMARY KEY,
            jira_issue_id TEXT,
            pr_url TEXT,
            status TEXT DEFAULT 'pending',
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
        self.conn.commit()

    def _migrate_columns(self):
        cur = self.conn.execute("PRAGMA table_info(crashes)")
        existing = {row[1] for row in cur.fetchall()}
        for name in _PIPELINE_FLAG_COLUMNS:
            if name not in existing:
                self.conn.execute(
                    f"ALTER TABLE crashes ADD COLUMN {name} INTEGER NOT NULL DEFAULT 0"
                )
        self.conn.commit()

    def insert_crash(self, crash_id: str):
        """Ensure a row exists for this crash without clobbering existing progress."""
        now = datetime.utcnow().isoformat()
        self.conn.execute(
            """
        INSERT OR IGNORE INTO crashes (crash_id, created_at, updated_at, status)
        VALUES (?, ?, ?, 'pending')
        """,
            (crash_id, now, now),
        )
        self.conn.commit()

    def update_result(self, crash_id: str, result: dict):
        now = datetime.utcnow().isoformat()
        self.conn.execute(
            """
        UPDATE crashes SET result = ?, updated_at = ? WHERE crash_id = ?
        """,
            (json.dumps(result), now, crash_id),
        )
        self.conn.commit()

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
        if sets:
            sets.append("updated_at = ?")
            vals.append(now)
            vals.append(crash_id)
            self.conn.execute(
                f"UPDATE crashes SET {', '.join(sets)} WHERE crash_id = ?",
                vals,
            )
        self._recompute_pipeline_complete(crash_id, now)
        self.conn.commit()

    def _recompute_pipeline_complete(self, crash_id: str, now_iso: str | None = None) -> None:
        """
        pipeline_complete when all required steps succeeded (Jira is optional).
        Required: analysis, fix generated, fix validated, diff applied, branch, MR.
        """
        now_iso = now_iso or datetime.utcnow().isoformat()
        row = self.conn.execute(
            f"""
            SELECT {", ".join(c for c in _PIPELINE_FLAG_COLUMNS if c != "pipeline_complete")}
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
        ) = row
        complete = int(
            bool(analysis_done)
            and bool(fix_generated)
            and bool(fix_validated)
            and bool(diff_applied)
            and bool(branch_created)
            and bool(mr_created)
        )
        status = "completed" if complete else "in_progress"
        self.conn.execute(
            """
            UPDATE crashes
            SET pipeline_complete = ?, status = ?, updated_at = ?
            WHERE crash_id = ?
            """,
            (complete, status, now_iso, crash_id),
        )

    def is_processed(self, crash_id: str) -> bool:
        """True when the full required pipeline finished (Jira not required)."""
        cursor = self.conn.execute(
            "SELECT pipeline_complete FROM crashes WHERE crash_id = ?",
            (crash_id,),
        )
        row = cursor.fetchone()
        return bool(row and row[0])
