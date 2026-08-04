from __future__ import annotations

import json
import os
from datetime import datetime
from typing import Any

import psycopg
from psycopg.rows import dict_row

from app.config import AI_CRASH_FIX_CRASH_DB_URL
from app.services.postgres_schema import connect_postgres, ensure_app_postgres_schema
from app.services.repo_registry_store import (
    RepoEntry,
    RepoIndexStatus,
    compute_repo_key,
    normalize_jira_create_mode,
    normalize_packages_dirs,
    row_to_repo_entry,
)
from app.services.user_context import resolve_user_id


def _crash_db_url() -> str:
    url = (
        (os.getenv("AI_CRASH_FIX_CRASH_DB_URL") or "").strip()
        or (AI_CRASH_FIX_CRASH_DB_URL or "").strip()
    )
    if not url:
        raise ValueError(
            "AI_CRASH_FIX_CRASH_DB_URL is required when AI_CRASH_FIX_CRASH_STORE_BACKEND=postgres"
        )
    return url


def _ts_to_str(value: Any) -> str | None:
    if value is None:
        return None
    if isinstance(value, str):
        return value.strip() or None
    try:
        return value.isoformat()
    except Exception:
        s = str(value).strip()
        return s or None


class PostgresRepoRegistryStore:
    """Postgres-backed repo registry scoped by the current user id."""

    def __init__(self) -> None:
        self.user_id = resolve_user_id(required=True)
        assert self.user_id is not None
        self.db_path = _crash_db_url()
        with self._connect() as conn:
            ensure_app_postgres_schema(conn)

    def _connect(self) -> psycopg.Connection:
        return connect_postgres(self.db_path, row_factory=dict_row)

    def list_repos(self) -> list[RepoEntry]:
        with self._connect() as conn:
            with conn.cursor() as cur:
                cur.execute(
                    """
                    SELECT * FROM repos
                    WHERE user_id = %s
                    ORDER BY updated_at DESC
                    """,
                    (self.user_id,),
                )
                rows = cur.fetchall()
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
        now = datetime.utcnow()

        with self._connect() as conn:
            with conn.cursor() as cur:
                cur.execute(
                    """
                    INSERT INTO repos(
                      user_id, repo_key, name, repo_url, repo_ref, firebase_project_id, access_token,
                      packages_dirs, crashlytics_fetch_backend, bq_dataset, bq_android_table, bq_ios_table,
                      jira_project_key, jira_server_url, jira_email, jira_token, jira_issue_type,
                      jira_create_fields, jira_create_mode, jira_parent_issue_key, gitlab_project,
                      crashlytics_android_package, crashlytics_ios_bundle_id,
                      created_at, updated_at, last_selected_at
                    )
                    VALUES (
                      %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s,
                      %s, %s, NULL
                    )
                    ON CONFLICT (user_id, repo_key) DO UPDATE SET
                      name = EXCLUDED.name,
                      repo_url = EXCLUDED.repo_url,
                      repo_ref = EXCLUDED.repo_ref,
                      firebase_project_id = EXCLUDED.firebase_project_id,
                      access_token = COALESCE(EXCLUDED.access_token, repos.access_token),
                      packages_dirs = EXCLUDED.packages_dirs,
                      crashlytics_fetch_backend = EXCLUDED.crashlytics_fetch_backend,
                      bq_dataset = EXCLUDED.bq_dataset,
                      bq_android_table = EXCLUDED.bq_android_table,
                      bq_ios_table = EXCLUDED.bq_ios_table,
                      jira_project_key = EXCLUDED.jira_project_key,
                      jira_server_url = EXCLUDED.jira_server_url,
                      jira_email = EXCLUDED.jira_email,
                      jira_token = COALESCE(EXCLUDED.jira_token, repos.jira_token),
                      jira_issue_type = EXCLUDED.jira_issue_type,
                      jira_create_fields = EXCLUDED.jira_create_fields,
                      jira_create_mode = EXCLUDED.jira_create_mode,
                      jira_parent_issue_key = EXCLUDED.jira_parent_issue_key,
                      gitlab_project = EXCLUDED.gitlab_project,
                      crashlytics_android_package = EXCLUDED.crashlytics_android_package,
                      crashlytics_ios_bundle_id = EXCLUDED.crashlytics_ios_bundle_id,
                      updated_at = EXCLUDED.updated_at
                    """,
                    (
                        self.user_id,
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
            with conn.cursor() as cur:
                cur.execute(
                    "SELECT * FROM repos WHERE user_id = %s AND repo_key = %s",
                    (self.user_id, key),
                )
                row = cur.fetchone()
        return row_to_repo_entry(row) if row else None

    def get_access_token(self, repo_key: str) -> str | None:
        key = (repo_key or "").strip()
        if not key:
            return None
        with self._connect() as conn:
            with conn.cursor() as cur:
                cur.execute(
                    "SELECT access_token FROM repos WHERE user_id = %s AND repo_key = %s",
                    (self.user_id, key),
                )
                row = cur.fetchone()
        if not row:
            return None
        v = row.get("access_token")
        if v is None:
            return None
        s = str(v).strip()
        if not s or s.lower() in {"none", "null"}:
            return None
        return s

    def get_jira_token(self, repo_key: str) -> str | None:
        key = (repo_key or "").strip()
        if not key:
            return None
        with self._connect() as conn:
            with conn.cursor() as cur:
                cur.execute(
                    "SELECT jira_token FROM repos WHERE user_id = %s AND repo_key = %s",
                    (self.user_id, key),
                )
                row = cur.fetchone()
        if not row:
            return None
        v = row.get("jira_token")
        if v is None:
            return None
        s = str(v).strip()
        if not s or s.lower() in {"none", "null"}:
            return None
        return s

    def get_google_application_credentials(self, repo_key: str) -> str | None:
        key = (repo_key or "").strip()
        if not key:
            return None
        with self._connect() as conn:
            with conn.cursor() as cur:
                cur.execute(
                    """
                    SELECT google_application_credentials
                    FROM repos WHERE user_id = %s AND repo_key = %s
                    """,
                    (self.user_id, key),
                )
                row = cur.fetchone()
        if not row:
            return None
        v = row.get("google_application_credentials")
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
        now = datetime.utcnow()
        with self._connect() as conn:
            with conn.cursor() as cur:
                cur.execute(
                    """
                    UPDATE repos
                    SET google_application_credentials = %s, updated_at = %s
                    WHERE user_id = %s AND repo_key = %s
                    """,
                    (creds, now, self.user_id, key),
                )
            conn.commit()
        out = self.get_repo(key)
        if out is None:
            raise RuntimeError("Failed to update google_application_credentials")
        return out

    def get_active_repo_key(self) -> str | None:
        with self._connect() as conn:
            with conn.cursor() as cur:
                cur.execute(
                    "SELECT v FROM app_state WHERE user_id = %s AND k = 'active_repo_key'",
                    (self.user_id,),
                )
                row = cur.fetchone()
        if not row:
            return None
        v = row.get("v")
        return str(v).strip() or None if v is not None else None

    def set_active_repo(self, repo_key: str) -> RepoEntry:
        key = (repo_key or "").strip()
        if not key:
            raise ValueError("repo_key is required")
        entry = self.get_repo(key)
        if entry is None:
            raise LookupError(f"repo_key={key!r} not found")
        now = datetime.utcnow()

        with self._connect() as conn:
            with conn.cursor() as cur:
                cur.execute(
                    """
                    INSERT INTO app_state(user_id, k, v) VALUES (%s, 'active_repo_key', %s)
                    ON CONFLICT (user_id, k) DO UPDATE SET v = EXCLUDED.v
                    """,
                    (self.user_id, key),
                )
                cur.execute(
                    """
                    UPDATE repos
                    SET last_selected_at = %s, updated_at = %s
                    WHERE user_id = %s AND repo_key = %s
                    """,
                    (now, now, self.user_id, key),
                )
            conn.commit()
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
            with conn.cursor() as cur:
                cur.execute(
                    "SELECT v FROM app_state WHERE user_id = %s AND k = 'active_repo_key'",
                    (self.user_id,),
                )
                active = cur.fetchone()
                if active and str(active.get("v") or "").strip() == key:
                    cur.execute(
                        "DELETE FROM app_state WHERE user_id = %s AND k = 'active_repo_key'",
                        (self.user_id,),
                    )
                cur.execute(
                    "DELETE FROM repos WHERE user_id = %s AND repo_key = %s",
                    (self.user_id, key),
                )
                if cur.rowcount == 0:
                    raise LookupError(f"repo_key={key!r} not found")
                cur.execute(
                    "DELETE FROM repo_indexes WHERE user_id = %s AND repo_key = %s",
                    (self.user_id, key),
                )
            conn.commit()


    def get_app_state(self, key: str) -> str | None:
        from app.services.user_context import resolve_user_id

        k = (key or "").strip()
        if not k:
            return None
        user_id = resolve_user_id(required=True)
        with self._connect() as conn:
            with conn.cursor() as cur:
                cur.execute(
                    "SELECT v FROM app_state WHERE user_id = %s AND k = %s",
                    (user_id, k),
                )
                row = cur.fetchone()
        if not row:
            return None
        v = row[0]
        if v is None:
            return None
        s = str(v).strip()
        return s or None

    def set_app_state(self, key: str, value: str | None) -> None:
        from app.services.user_context import resolve_user_id

        k = (key or "").strip()
        if not k:
            raise ValueError("app_state key is required")
        user_id = resolve_user_id(required=True)
        with self._connect() as conn:
            with conn.cursor() as cur:
                if value is None or not str(value).strip():
                    cur.execute(
                        "DELETE FROM app_state WHERE user_id = %s AND k = %s",
                        (user_id, k),
                    )
                else:
                    cur.execute(
                        """
                        INSERT INTO app_state(user_id, k, v) VALUES (%s, %s, %s)
                        ON CONFLICT (user_id, k) DO UPDATE SET v = EXCLUDED.v
                        """,
                        (user_id, k, str(value).strip()),
                    )
            conn.commit()

    def get_index_status(self, repo_key: str) -> RepoIndexStatus | None:
        key = (repo_key or "").strip()
        if not key:
            return None
        with self._connect() as conn:
            with conn.cursor() as cur:
                cur.execute(
                    "SELECT * FROM repo_indexes WHERE user_id = %s AND repo_key = %s",
                    (self.user_id, key),
                )
                row = cur.fetchone()
        if not row:
            return None
        last_indexed = row.get("last_indexed_at")
        return RepoIndexStatus(
            repo_key=row["repo_key"],
            indexed_sha=(str(row["indexed_sha"]).strip() or None) if row.get("indexed_sha") is not None else None,
            last_indexed_at=_ts_to_str(last_indexed),
            last_error=(str(row["last_error"]).strip() or None) if row.get("last_error") is not None else None,
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
            with conn.cursor() as cur:
                cur.execute(
                    """
                    INSERT INTO repo_indexes(user_id, repo_key, indexed_sha, last_indexed_at, last_error)
                    VALUES (%s, %s, %s, %s, %s)
                    ON CONFLICT (user_id, repo_key) DO UPDATE SET
                      indexed_sha = EXCLUDED.indexed_sha,
                      last_indexed_at = EXCLUDED.last_indexed_at,
                      last_error = EXCLUDED.last_error
                    """,
                    (self.user_id, key, sha, ts, err),
                )
            conn.commit()
        return RepoIndexStatus(repo_key=key, indexed_sha=sha, last_indexed_at=ts, last_error=err)
