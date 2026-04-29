import json
import sqlite3
from pathlib import Path
from datetime import datetime
from app.config import BQ_PROJECT_ID


class CrashStore:

    def __init__(self, db_path=f"db/{BQ_PROJECT_ID}_crash_store.db"):
        # sqlite won't create parent folders automatically
        Path(db_path).expanduser().resolve().parent.mkdir(parents=True, exist_ok=True)
        self.conn = sqlite3.connect(db_path)
        self._create_table()

    def _create_table(self):
        self.conn.execute("""
        CREATE TABLE IF NOT EXISTS crashes (
            crash_id TEXT PRIMARY KEY,
            jira_issue_id TEXT,
            status TEXT DEFAULT "pending",
            created_at TEXT DEFAULT CURRENT_TIMESTAMP,
            updated_at TEXT DEFAULT CURRENT_TIMESTAMP,
            result TEXT DEFAULT NULL
        )
        """)
        self.conn.commit()

    def insert_crash(self, crash_id: str,):
        now = datetime.utcnow().isoformat()
        self.conn.execute("""
        INSERT INTO crashes (crash_id, jira_issue_id, status, created_at, updated_at, result)
        VALUES (?, ?, ?, ?, ?, ?)
        ON CONFLICT(crash_id) DO UPDATE SET
            jira_issue_id = excluded.jira_issue_id,
            status = excluded.status,
            updated_at = excluded.updated_at,
            result = excluded.result
        """, (crash_id, None, "pending", now, now, None))
        self.conn.commit()

    def update_result(self, crash_id: str, result: dict):
        self.conn.execute("""
        UPDATE crashes SET result = ? WHERE crash_id = ?
        """, (json.dumps(result), crash_id))
        self.conn.commit()

    def mark_processed(self, crash_id: str, jira_issue_id: str = None):
        self.conn.execute("""
        INSERT OR REPLACE INTO crashes (crash_id, jira_issue_id, status, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?)
        """, (crash_id, jira_issue_id, "completed", datetime.utcnow().isoformat(), datetime.utcnow().isoformat()))
        self.conn.commit()

    def is_processed(self, crash_id: str) -> bool:
        cursor = self.conn.execute("""
        SELECT status FROM crashes WHERE crash_id=? AND status = "completed"
        """, (crash_id,))
        row = cursor.fetchone()
        if not row:
            return False
        return row[0] == "completed"
