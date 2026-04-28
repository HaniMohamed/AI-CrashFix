import sqlite3
from datetime import datetime


class CrashStore:

    def __init__(self, db_path="crash_store.db"):
        self.conn = sqlite3.connect(db_path)
        self._create_table()

    def _create_table(self):
        self.conn.execute("""
        CREATE TABLE IF NOT EXISTS crashes (
            crash_id TEXT PRIMARY KEY,
            jira_issue_id TEXT,
            status TEXT DEFAULT "pending",
            created_at TEXT DEFAULT CURRENT_TIMESTAMP
            updated_at TEXT DEFAULT CURRENT_TIMESTAMP
        )
        """)
        self.conn.commit()

    def insert_crash(self, crash_id: str,):
        self.conn.execute("""
        INSERT INTO crashes (crash_id, jira_issue_id, status, created_at)
        VALUES (?, ?, ?, ?)
        """, (crash_id, None, "pending", datetime.utcnow().isoformat()))
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
        return cursor.fetchone()[0] == "completed"
