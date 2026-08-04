from __future__ import annotations

from typing import Any

import psycopg

DEFAULT_POSTGRES_CONNECT_TIMEOUT = 3


def connect_postgres(
    url: str,
    *,
    row_factory: Any | None = None,
    connect_timeout: int = DEFAULT_POSTGRES_CONNECT_TIMEOUT,
) -> psycopg.Connection:
    """Open Postgres with a bounded connect wait (avoids blocking API startup)."""
    kwargs: dict[str, Any] = {"connect_timeout": max(1, int(connect_timeout))}
    if row_factory is not None:
        kwargs["row_factory"] = row_factory
    return psycopg.connect(url, **kwargs)

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
  created_by_user_id TEXT,
  PRIMARY KEY (firebase_project_id, crash_id)
);
CREATE INDEX IF NOT EXISTS idx_crashes_project_updated
  ON crashes (firebase_project_id, updated_at DESC);

CREATE TABLE IF NOT EXISTS repos (
  user_id TEXT NOT NULL,
  repo_key TEXT NOT NULL,
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
  jira_server_url TEXT,
  jira_email TEXT,
  jira_token TEXT,
  jira_issue_type TEXT,
  jira_create_fields TEXT,
  jira_create_mode TEXT,
  jira_parent_issue_key TEXT,
  gitlab_project TEXT,
  crashlytics_android_package TEXT,
  crashlytics_ios_bundle_id TEXT,
  google_application_credentials TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  last_selected_at TIMESTAMPTZ,
  PRIMARY KEY (user_id, repo_key)
);
CREATE INDEX IF NOT EXISTS idx_repos_user_updated
  ON repos (user_id, updated_at DESC);

CREATE TABLE IF NOT EXISTS app_settings (
  user_id TEXT NOT NULL,
  k TEXT NOT NULL,
  v JSONB,
  updated_at TIMESTAMPTZ,
  PRIMARY KEY (user_id, k)
);
CREATE INDEX IF NOT EXISTS idx_app_settings_user_updated
  ON app_settings (user_id, updated_at DESC);

CREATE TABLE IF NOT EXISTS app_state (
  user_id TEXT NOT NULL,
  k TEXT NOT NULL,
  v TEXT,
  PRIMARY KEY (user_id, k)
);

CREATE TABLE IF NOT EXISTS repo_indexes (
  user_id TEXT NOT NULL,
  repo_key TEXT NOT NULL,
  indexed_sha TEXT,
  last_indexed_at TIMESTAMPTZ,
  last_error TEXT,
  PRIMARY KEY (user_id, repo_key)
);
"""


_schema_ready = False


def ensure_app_postgres_schema(conn: psycopg.Connection) -> None:
    """Create/migrate the unified Postgres app store schema (process-level once)."""
    global _schema_ready
    if _schema_ready:
        return
    with conn.cursor() as cur:
        for statement in (part.strip() for part in _SCHEMA_SQL.split(";")):
            if statement:
                cur.execute(statement)
        # Existing DBs may predate created_by_user_id — add then index.
        cur.execute(
            "ALTER TABLE crashes ADD COLUMN IF NOT EXISTS created_by_user_id TEXT"
        )
        cur.execute(
            "ALTER TABLE repos ADD COLUMN IF NOT EXISTS google_application_credentials TEXT"
        )
        cur.execute(
            "CREATE INDEX IF NOT EXISTS idx_crashes_created_by ON crashes (created_by_user_id)"
        )
    conn.commit()
    _schema_ready = True


def reset_schema_ready_for_tests() -> None:
    """Allow tests to re-run schema ensure after resetting connections."""
    global _schema_ready
    _schema_ready = False
