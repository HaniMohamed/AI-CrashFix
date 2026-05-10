from __future__ import annotations

import hashlib
import json
import os
import sqlite3
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Iterable


def _data_dir() -> Path | None:
    raw = (os.environ.get("AI_CRASH_FIX_DATA_DIR") or "").strip()
    if not raw:
        return None
    try:
        return Path(raw).expanduser().resolve()
    except Exception:
        return None


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
    firebase_project_id: str | None
    has_token: bool
    packages_dirs: list[str]
    crashlytics_fetch_backend: str | None
    bq_dataset: str | None
    bq_android_table: str | None
    bq_ios_table: str | None
    jira_project_key: str | None
    gitlab_project: str | None
    created_at: str
    updated_at: str
    last_selected_at: str | None


@dataclass(frozen=True)
class RepoIndexStatus:
    repo_key: str
    indexed_sha: str | None
    last_indexed_at: str | None
    last_error: str | None


def normalize_packages_dirs(value: str | list[str] | None) -> list[str]:
    """
    Normalize user-provided package roots (repo-scoped).

    Accepts:
    - None
    - list[str]
    - JSON-encoded list[str] (stored format)
    - comma-separated string (legacy / UI convenience)
    """
    if value is None:
        return []
    raw: list[str] = []
    if isinstance(value, list):
        raw = [str(x) for x in value]
    else:
        s = str(value).strip()
        if not s:
            return []
        # Prefer JSON storage format.
        if s.startswith("[") and s.endswith("]"):
            try:
                parsed = json.loads(s)
                if isinstance(parsed, list):
                    raw = [str(x) for x in parsed]
                else:
                    raw = []
            except Exception:
                raw = []
        else:
            raw = [p.strip() for p in s.split(",")]

    out: list[str] = []
    seen: set[str] = set()
    for p in raw:
        p = (p or "").strip().strip("/").strip()
        if not p:
            continue
        # Keep it safe: repo-relative only.
        if p.startswith(("/", "\\")):
            continue
        if ".." in p.split("/"):
            continue
        if p in seen:
            continue
        seen.add(p)
        out.append(p)
    return out


class RepoRegistryStore:
    """
    Global repo registry stored in a single SQLite DB.

    This is intentionally separate from the per-repo crash DBs.
    """

    def __init__(self, db_path: str | None = None) -> None:
        path = (db_path or os.environ.get("AI_CRASH_FIX_REPO_REGISTRY_DB") or "").strip()
        if not path:
            base = _data_dir()
            if base is not None:
                path = os.fspath((base / "db" / "repo_registry.db").resolve())
            else:
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
                    firebase_project_id TEXT,
                    access_token TEXT,
                    packages_dirs TEXT,
                    crashlytics_fetch_backend TEXT,
                    bq_dataset TEXT,
                    bq_android_table TEXT,
                    bq_ios_table TEXT,
                    jira_project_key TEXT,
                    gitlab_project TEXT,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL,
                    last_selected_at TEXT
                )
                """
            )
            # Migrate older DBs missing columns.
            cur = conn.execute("PRAGMA table_info(repos)")
            existing = {row[1] for row in cur.fetchall()}
            if "access_token" not in existing:
                conn.execute("ALTER TABLE repos ADD COLUMN access_token TEXT")
            if "firebase_project_id" not in existing:
                conn.execute("ALTER TABLE repos ADD COLUMN firebase_project_id TEXT")
            if "packages_dirs" not in existing:
                conn.execute("ALTER TABLE repos ADD COLUMN packages_dirs TEXT")
            if "crashlytics_fetch_backend" not in existing:
                conn.execute("ALTER TABLE repos ADD COLUMN crashlytics_fetch_backend TEXT")
            if "bq_dataset" not in existing:
                conn.execute("ALTER TABLE repos ADD COLUMN bq_dataset TEXT")
            if "bq_android_table" not in existing:
                conn.execute("ALTER TABLE repos ADD COLUMN bq_android_table TEXT")
            if "bq_ios_table" not in existing:
                conn.execute("ALTER TABLE repos ADD COLUMN bq_ios_table TEXT")
            if "jira_project_key" not in existing:
                conn.execute("ALTER TABLE repos ADD COLUMN jira_project_key TEXT")
            if "gitlab_project" not in existing:
                conn.execute("ALTER TABLE repos ADD COLUMN gitlab_project TEXT")
            conn.execute(
                """
                CREATE TABLE IF NOT EXISTS app_state (
                    k TEXT PRIMARY KEY,
                    v TEXT
                )
                """
            )
            conn.execute(
                """
                CREATE TABLE IF NOT EXISTS repo_indexes (
                    repo_key TEXT PRIMARY KEY,
                    indexed_sha TEXT,
                    last_indexed_at TEXT,
                    last_error TEXT
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

    def upsert_repo(
        self,
        *,
        name: str,
        repo_url: str,
        repo_ref: str | None,
        firebase_project_id: str | None = None,
        access_token: str | None = None,
        packages_dirs: str | list[str] | None = None,
        crashlytics_fetch_backend: str | None = None,
        bq_dataset: str | None = None,
        bq_android_table: str | None = None,
        bq_ios_table: str | None = None,
        jira_project_key: str | None = None,
        gitlab_project: str | None = None,
    ) -> RepoEntry:
        url = (repo_url or "").strip()
        if not url:
            raise ValueError("repo_url is required")
        nm = (name or "").strip()
        if not nm:
            raise ValueError("name is required")
        ref = (repo_ref or "").strip() or None
        fpid = (firebase_project_id or "").strip() or None
        tok = (access_token or "").strip() or None
        pdirs = normalize_packages_dirs(packages_dirs)
        pdirs_json = json.dumps(pdirs, ensure_ascii=False)
        cl_backend = (crashlytics_fetch_backend or "").strip().lower() or None
        ds = (bq_dataset or "").strip() or None
        at = (bq_android_table or "").strip() or None
        it = (bq_ios_table or "").strip() or None
        jira_pk = (jira_project_key or "").strip() or None
        gl_proj = (gitlab_project or "").strip() or None

        repo_key = compute_repo_key(repo_url=url, repo_ref=ref)
        now = datetime.utcnow().isoformat()

        with self._connect() as conn:
            conn.execute(
                """
                INSERT INTO repos(
                  repo_key, name, repo_url, repo_ref, firebase_project_id, access_token, packages_dirs,
                  crashlytics_fetch_backend, bq_dataset, bq_android_table, bq_ios_table,
                  jira_project_key, gitlab_project,
                  created_at, updated_at, last_selected_at
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL)
                ON CONFLICT(repo_key) DO UPDATE SET
                  name = excluded.name,
                  repo_url = excluded.repo_url,
                  repo_ref = excluded.repo_ref,
                  firebase_project_id = excluded.firebase_project_id,
                  access_token = COALESCE(excluded.access_token, repos.access_token),
                  packages_dirs = excluded.packages_dirs,
                  crashlytics_fetch_backend = excluded.crashlytics_fetch_backend,
                  bq_dataset = excluded.bq_dataset,
                  bq_android_table = excluded.bq_android_table,
                  bq_ios_table = excluded.bq_ios_table,
                  jira_project_key = excluded.jira_project_key,
                  gitlab_project = excluded.gitlab_project,
                  updated_at = excluded.updated_at
                """,
                (
                    repo_key,
                    nm,
                    url,
                    ref,
                    fpid,
                    tok,
                    pdirs_json,
                    cl_backend,
                    ds,
                    at,
                    it,
                    jira_pk,
                    gl_proj,
                    now,
                    now,
                ),
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

    def get_access_token(self, repo_key: str) -> str | None:
        key = (repo_key or "").strip()
        if not key:
            return None
        with self._connect() as conn:
            row = conn.execute(
                "SELECT access_token FROM repos WHERE repo_key = ?",
                (key,),
            ).fetchone()
        if not row:
            return None
        v = row[0]
        if v is None:
            return None
        s = str(v).strip()
        if not s:
            return None
        # Guard against accidental stringification of null-like values.
        if s.lower() in {"none", "null"}:
            return None
        return s

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

    def delete_repo(self, repo_key: str) -> None:
        key = (repo_key or "").strip()
        if not key:
            raise ValueError("repo_key is required")
        with self._connect() as conn:
            # If active repo is being deleted, clear selection.
            active = conn.execute(
                "SELECT v FROM app_state WHERE k = 'active_repo_key'"
            ).fetchone()
            if active and str(active[0]).strip() == key:
                conn.execute("DELETE FROM app_state WHERE k = 'active_repo_key'")
            cur = conn.execute("DELETE FROM repos WHERE repo_key = ?", (key,))
            if cur.rowcount == 0:
                raise LookupError(f"repo_key={key!r} not found")
            conn.execute("DELETE FROM repo_indexes WHERE repo_key = ?", (key,))
            conn.commit()

    def get_index_status(self, repo_key: str) -> RepoIndexStatus | None:
        key = (repo_key or "").strip()
        if not key:
            return None
        with self._connect() as conn:
            conn.row_factory = sqlite3.Row
            row = conn.execute(
                "SELECT * FROM repo_indexes WHERE repo_key = ?",
                (key,),
            ).fetchone()
        if not row:
            return None
        return RepoIndexStatus(
            repo_key=row["repo_key"],
            indexed_sha=(str(row["indexed_sha"]).strip() or None) if row["indexed_sha"] is not None else None,
            last_indexed_at=(str(row["last_indexed_at"]).strip() or None)
            if row["last_indexed_at"] is not None
            else None,
            last_error=(str(row["last_error"]).strip() or None) if row["last_error"] is not None else None,
        )

    def upsert_index_status(
        self,
        *,
        repo_key: str,
        indexed_sha: str | None,
        last_indexed_at: str | None,
        last_error: str | None,
    ) -> RepoIndexStatus:
        key = (repo_key or "").strip()
        if not key:
            raise ValueError("repo_key is required")
        sha = (indexed_sha or "").strip() or None
        ts = (last_indexed_at or "").strip() or None
        err = (last_error or "").strip() or None
        with self._connect() as conn:
            conn.execute(
                """
                INSERT INTO repo_indexes(repo_key, indexed_sha, last_indexed_at, last_error)
                VALUES (?, ?, ?, ?)
                ON CONFLICT(repo_key) DO UPDATE SET
                  indexed_sha = excluded.indexed_sha,
                  last_indexed_at = excluded.last_indexed_at,
                  last_error = excluded.last_error
                """,
                (key, sha, ts, err),
            )
            conn.commit()
        return RepoIndexStatus(repo_key=key, indexed_sha=sha, last_indexed_at=ts, last_error=err)

    @staticmethod
    def _row_to_entry(row: sqlite3.Row) -> RepoEntry:
        pdirs = []
        if "packages_dirs" in row.keys():
            pdirs = normalize_packages_dirs(row["packages_dirs"])
        return RepoEntry(
            repo_key=row["repo_key"],
            name=row["name"],
            repo_url=row["repo_url"],
            repo_ref=row["repo_ref"] if row["repo_ref"] else None,
            firebase_project_id=row["firebase_project_id"] if row["firebase_project_id"] else None,
            has_token=bool(row["access_token"]) if "access_token" in row.keys() else False,
            packages_dirs=pdirs,
            crashlytics_fetch_backend=row["crashlytics_fetch_backend"]
            if "crashlytics_fetch_backend" in row.keys() and row["crashlytics_fetch_backend"]
            else None,
            bq_dataset=row["bq_dataset"] if "bq_dataset" in row.keys() and row["bq_dataset"] else None,
            bq_android_table=row["bq_android_table"]
            if "bq_android_table" in row.keys() and row["bq_android_table"]
            else None,
            bq_ios_table=row["bq_ios_table"] if "bq_ios_table" in row.keys() and row["bq_ios_table"] else None,
            jira_project_key=row["jira_project_key"]
            if "jira_project_key" in row.keys() and row["jira_project_key"]
            else None,
            gitlab_project=row["gitlab_project"] if "gitlab_project" in row.keys() and row["gitlab_project"] else None,
            created_at=row["created_at"],
            updated_at=row["updated_at"],
            last_selected_at=row["last_selected_at"] if row["last_selected_at"] else None,
        )

