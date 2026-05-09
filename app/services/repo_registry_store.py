from __future__ import annotations

import hashlib
import os
import sqlite3
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path


def compute_repo_key(*, repo_url: str, repo_ref: str | None) -> str:
    """
    Stable 12-char key derived from repo_url + repo_ref.
    Must match the key used by ProjectService.prepare_repo().
    """
    url = (repo_url or "").strip()
    ref = (repo_ref or "").strip() or ""
    if not url:
        raise ValueError("repo_url is required")
    key = f"{url}@{ref}".encode("utf-8")
    return hashlib.sha1(key).hexdigest()[:12]


@dataclass(frozen=True)
class RepoEntry:
    repo_key: str
    name: str
    repo_url: str
    repo_ref: str | None
    created_at: str
    updated_at: str
    last_selected_at: str | None


class RepoRegistryStore:
    """
    Global repo registry stored in a single SQLite DB.

    This is intentionally separate from the per-repo crash DBs.
    """

    def __init__(self, db_path: str | None = None) -> None:
        path = (db_path or os.environ.get("AI_CRASH_FIX_REPO_REGISTRY_DB") or "").strip()
        if not path:
            path = "db/repo_registry.db"
        p = Path(path).expanduser().resolve()
        p.parent.mkdir(parents=True, exist_ok=True)
        self.db_path = str(p)
        self._ensure_schema()

    def _connect(self) -> sqlite3.Connection:
        return sqlite3.connect(self.db_path, timeout=30.0)

    def _ensure_schema(self) -> None:
        with self._connect() as conn:
            conn.execute(
                """
                CREATE TABLE IF NOT EXISTS repos (
                    repo_key TEXT PRIMARY KEY,
                    name TEXT NOT NULL,
                    repo_url TEXT NOT NULL,
                    repo_ref TEXT,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL,
                    last_selected_at TEXT
                )
                """
            )
            conn.execute(
                """
                CREATE TABLE IF NOT EXISTS app_state (
                    k TEXT PRIMARY KEY,
                    v TEXT
                )
                """
            )
            conn.execute(
                "CREATE INDEX IF NOT EXISTS idx_repos_updated_at ON repos(updated_at)"
            )
            conn.commit()

    def list_repos(self) -> list[RepoEntry]:
        with self._connect() as conn:
            conn.row_factory = sqlite3.Row
            rows = conn.execute(
                "SELECT * FROM repos ORDER BY datetime(updated_at) DESC"
            ).fetchall()
        return [self._row_to_entry(r) for r in rows]

    def upsert_repo(self, *, name: str, repo_url: str, repo_ref: str | None) -> RepoEntry:
        url = (repo_url or "").strip()
        if not url:
            raise ValueError("repo_url is required")
        nm = (name or "").strip()
        if not nm:
            raise ValueError("name is required")
        ref = (repo_ref or "").strip() or None

        repo_key = compute_repo_key(repo_url=url, repo_ref=ref)
        now = datetime.utcnow().isoformat()

        with self._connect() as conn:
            conn.execute(
                """
                INSERT INTO repos(repo_key, name, repo_url, repo_ref, created_at, updated_at, last_selected_at)
                VALUES (?, ?, ?, ?, ?, ?, NULL)
                ON CONFLICT(repo_key) DO UPDATE SET
                  name = excluded.name,
                  repo_url = excluded.repo_url,
                  repo_ref = excluded.repo_ref,
                  updated_at = excluded.updated_at
                """,
                (repo_key, nm, url, ref, now, now),
            )
            conn.commit()

        entry = self.get_repo(repo_key)
        if entry is None:
            raise RuntimeError("Failed to upsert repo")
        return entry

    def get_repo(self, repo_key: str) -> RepoEntry | None:
        key = (repo_key or "").strip()
        if not key:
            return None
        with self._connect() as conn:
            conn.row_factory = sqlite3.Row
            row = conn.execute("SELECT * FROM repos WHERE repo_key = ?", (key,)).fetchone()
        return self._row_to_entry(row) if row else None

    def get_active_repo_key(self) -> str | None:
        with self._connect() as conn:
            row = conn.execute(
                "SELECT v FROM app_state WHERE k = 'active_repo_key'"
            ).fetchone()
        if not row:
            return None
        v = row[0]
        return str(v).strip() or None

    def set_active_repo(self, repo_key: str) -> RepoEntry:
        key = (repo_key or "").strip()
        if not key:
            raise ValueError("repo_key is required")
        entry = self.get_repo(key)
        if entry is None:
            raise LookupError(f"repo_key={key!r} not found")
        now = datetime.utcnow().isoformat()

        with self._connect() as conn:
            conn.execute(
                "INSERT INTO app_state(k, v) VALUES('active_repo_key', ?) "
                "ON CONFLICT(k) DO UPDATE SET v = excluded.v",
                (key,),
            )
            conn.execute(
                "UPDATE repos SET last_selected_at = ?, updated_at = ? WHERE repo_key = ?",
                (now, now, key),
            )
            conn.commit()
        # Re-read for updated timestamps.
        refreshed = self.get_repo(key)
        if refreshed is None:
            raise RuntimeError("Failed to set active repo")
        return refreshed

    def get_active_repo(self) -> RepoEntry | None:
        key = self.get_active_repo_key()
        if not key:
            return None
        return self.get_repo(key)

    @staticmethod
    def _row_to_entry(row: sqlite3.Row) -> RepoEntry:
        return RepoEntry(
            repo_key=row["repo_key"],
            name=row["name"],
            repo_url=row["repo_url"],
            repo_ref=row["repo_ref"] if row["repo_ref"] else None,
            created_at=row["created_at"],
            updated_at=row["updated_at"],
            last_selected_at=row["last_selected_at"] if row["last_selected_at"] else None,
        )

