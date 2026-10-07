from __future__ import annotations

import json
import sqlite3
from datetime import datetime, timezone

from app.services.repo_registry_store import (
    RepoEntry,
    RepoIndexStatus,
    compute_repo_key,
    normalize_jira_create_mode,
    normalize_packages_dirs,
    resolve_repo_registry_db_path,
    row_to_repo_entry,
)
from app.services.sqlite_util import (
    connect_sqlite,
    mark_schema_ensured,
    schema_needs_ensure,
)


class SqliteRepoRegistryStore:
    """
    Global repo registry stored in a single SQLite DB.

    This is intentionally separate from the per-repo crash DBs.
    """

    def __init__(self, db_path: str | None = None) -> None:
        self.db_path = resolve_repo_registry_db_path(db_path)
        self._ensure_schema()

    def _connect(self):
        return connect_sqlite(self.db_path)

    def _ensure_schema(self) -> None:
        if not schema_needs_ensure(f"repo_registry:{self.db_path}"):
            return
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
            if "jira_server_url" not in existing:
                conn.execute("ALTER TABLE repos ADD COLUMN jira_server_url TEXT")
            if "jira_email" not in existing:
                conn.execute("ALTER TABLE repos ADD COLUMN jira_email TEXT")
            if "jira_token" not in existing:
                conn.execute("ALTER TABLE repos ADD COLUMN jira_token TEXT")
            if "jira_issue_type" not in existing:
                conn.execute("ALTER TABLE repos ADD COLUMN jira_issue_type TEXT")
            if "jira_create_fields" not in existing:
                conn.execute("ALTER TABLE repos ADD COLUMN jira_create_fields TEXT")
            if "jira_create_mode" not in existing:
                conn.execute("ALTER TABLE repos ADD COLUMN jira_create_mode TEXT")
            if "jira_parent_issue_key" not in existing:
                conn.execute("ALTER TABLE repos ADD COLUMN jira_parent_issue_key TEXT")
            if "crashlytics_android_package" not in existing:
                conn.execute("ALTER TABLE repos ADD COLUMN crashlytics_android_package TEXT")
            if "crashlytics_ios_bundle_id" not in existing:
                conn.execute("ALTER TABLE repos ADD COLUMN crashlytics_ios_bundle_id TEXT")
            if "google_application_credentials" not in existing:
                conn.execute("ALTER TABLE repos ADD COLUMN google_application_credentials TEXT")
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
        mark_schema_ensured(f"repo_registry:{self.db_path}")

    def list_repos(self) -> list[RepoEntry]:
        with self._connect() as conn:
            conn.row_factory = sqlite3.Row
            rows = conn.execute(
                "SELECT * FROM repos ORDER BY datetime(updated_at) DESC"
            ).fetchall()
        return [row_to_repo_entry(r) for r in rows]

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
        jira_server_url: str | None = None,
        jira_email: str | None = None,
        jira_token: str | None = None,
        jira_issue_type: str | None = None,
        jira_create_fields: str | None = None,
        jira_create_mode: str | None = None,
        jira_parent_issue_key: str | None = None,
        gitlab_project: str | None = None,
        crashlytics_android_package: str | None = None,
        crashlytics_ios_bundle_id: str | None = None,
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
        jira_url = (jira_server_url or "").strip() or None
        jira_em = (jira_email or "").strip() or None
        jira_tok = (jira_token or "").strip() or None
        jira_it = (jira_issue_type or "").strip() or None
        jira_cf = (jira_create_fields or "").strip() or None
        jira_mode = normalize_jira_create_mode(jira_create_mode)
        jira_parent = (jira_parent_issue_key or "").strip().upper() or None
        from app.utils.gitlab_url import derive_gitlab_project_path_from_repo_url

        gl_proj = (gitlab_project or "").strip() or derive_gitlab_project_path_from_repo_url(url) or None
        cl_android = (crashlytics_android_package or "").strip() or None
        cl_ios = (crashlytics_ios_bundle_id or "").strip() or None

        repo_key = compute_repo_key(repo_url=url, repo_ref=ref)
        now = datetime.now(timezone.utc).isoformat()

        with self._connect() as conn:
            conn.execute(
                """
                INSERT INTO repos(
                  repo_key, name, repo_url, repo_ref, firebase_project_id, access_token, packages_dirs,
                  crashlytics_fetch_backend, bq_dataset, bq_android_table, bq_ios_table,
                  jira_project_key, jira_server_url, jira_email, jira_token, jira_issue_type,
                  jira_create_fields, jira_create_mode, jira_parent_issue_key, gitlab_project,
                  crashlytics_android_package, crashlytics_ios_bundle_id,
                  created_at, updated_at, last_selected_at
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL)
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
                  jira_server_url = excluded.jira_server_url,
                  jira_email = excluded.jira_email,
                  jira_token = COALESCE(excluded.jira_token, repos.jira_token),
                  jira_issue_type = excluded.jira_issue_type,
                  jira_create_fields = excluded.jira_create_fields,
                  jira_create_mode = excluded.jira_create_mode,
                  jira_parent_issue_key = excluded.jira_parent_issue_key,
                  gitlab_project = excluded.gitlab_project,
                  crashlytics_android_package = excluded.crashlytics_android_package,
                  crashlytics_ios_bundle_id = excluded.crashlytics_ios_bundle_id,
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
                    jira_url,
                    jira_em,
                    jira_tok,
                    jira_it,
                    jira_cf,
                    jira_mode,
                    jira_parent,
                    gl_proj,
                    cl_android,
                    cl_ios,
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
        return row_to_repo_entry(row) if row else None

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

    def get_jira_token(self, repo_key: str) -> str | None:
        key = (repo_key or "").strip()
        if not key:
            return None
        with self._connect() as conn:
            row = conn.execute(
                "SELECT jira_token FROM repos WHERE repo_key = ?",
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
        if s.lower() in {"none", "null"}:
            return None
        return s

    def get_google_application_credentials(self, repo_key: str) -> str | None:
        key = (repo_key or "").strip()
        if not key:
            return None
        with self._connect() as conn:
            row = conn.execute(
                "SELECT google_application_credentials FROM repos WHERE repo_key = ?",
                (key,),
            ).fetchone()
        if not row:
            return None
        v = row[0]
        if v is None:
            return None
        s = str(v).strip()
        if not s or s.lower() in {"none", "null"}:
            return None
        return s

    def set_google_application_credentials(self, repo_key: str, path: str | None) -> RepoEntry:
        key = (repo_key or "").strip()
        if not key:
            raise ValueError("repo_key is required")
        entry = self.get_repo(key)
        if entry is None:
            raise LookupError(f"repo_key={key!r} not found")
        creds = (path or "").strip() or None
        now = datetime.now(timezone.utc).isoformat()
        with self._connect() as conn:
            conn.execute(
                """
                UPDATE repos
                SET google_application_credentials = ?, updated_at = ?
                WHERE repo_key = ?
                """,
                (creds, now, key),
            )
            conn.commit()
        out = self.get_repo(key)
        if out is None:
            raise RuntimeError("Failed to update google_application_credentials")
        return out

    def clear_legacy_repo_jira_base_config(self, repo_key: str) -> RepoEntry:
        key = (repo_key or "").strip()
        if not key:
            raise ValueError("repo_key is required")
        entry = self.get_repo(key)
        if entry is None:
            raise LookupError(f"repo_key={key!r} not found")
        now = datetime.now(timezone.utc).isoformat()
        with self._connect() as conn:
            conn.execute(
                """
                UPDATE repos
                SET jira_server_url = NULL,
                    jira_email = NULL,
                    jira_token = NULL,
                    updated_at = ?
                WHERE repo_key = ?
                """,
                (now, key),
            )
            conn.commit()
        out = self.get_repo(key)
        if out is None:
            raise RuntimeError("Failed to clear legacy repo Jira base config")
        return out

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
        now = datetime.now(timezone.utc).isoformat()

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


    def get_app_state(self, key: str) -> str | None:
        k = (key or "").strip()
        if not k:
            return None
        with self._connect() as conn:
            row = conn.execute(
                "SELECT v FROM app_state WHERE k = ?",
                (k,),
            ).fetchone()
        if not row:
            return None
        v = row[0]
        if v is None:
            return None
        s = str(v).strip()
        return s or None

    def set_app_state(self, key: str, value: str | None) -> None:
        k = (key or "").strip()
        if not k:
            raise ValueError("app_state key is required")
        with self._connect() as conn:
            if value is None or not str(value).strip():
                conn.execute("DELETE FROM app_state WHERE k = ?", (k,))
            else:
                conn.execute(
                    "INSERT INTO app_state(k, v) VALUES(?, ?) "
                    "ON CONFLICT(k) DO UPDATE SET v = excluded.v",
                    (k, str(value).strip()),
                )
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
