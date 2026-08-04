#!/usr/bin/env python3
"""Copy per-user repo configuration from one Postgres user to another.

Copies repos, app_settings, app_state, and repo_indexes (not crash rows).

The target user must still launch the app with matching identity and database
reachability in ``~/crash_fix_gosi_brain_conf.env`` (or ``AI_CRASH_FIX_ENV_FILE``):

- ``AI_CRASH_FIX_USER_ID=<to-user>`` (same id passed to ``--to-user``)
- ``AI_CRASH_FIX_CRASH_STORE_BACKEND=postgres``
- ``AI_CRASH_FIX_CRASH_DB_URL=...`` pointing at the **same** shared Postgres
  host where this script writes (not ``localhost`` unless Postgres runs on
  that user's machine)

Example:

  python scripts/copy_user_repo_data.py \\
    --from-user cr231120 \\
    --to-user newuser123 \\
    --dry-run

  python scripts/copy_user_repo_data.py \\
    --from-user cr231120 \\
    --to-user newuser123
"""

from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path
from typing import Any

PROJECT_ROOT = Path(__file__).resolve().parents[1]
if str(PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(PROJECT_ROOT))

# Load .env so AI_CRASH_FIX_CRASH_DB_URL is available without --url.
from app import config as _cfg  # noqa: F401

import psycopg
from psycopg.types.json import Json

from app.services.postgres_schema import ensure_app_postgres_schema
from app.services.user_context import normalize_user_id

_REPO_COLUMNS = (
    "repo_key",
    "name",
    "repo_url",
    "repo_ref",
    "firebase_project_id",
    "access_token",
    "packages_dirs",
    "crashlytics_fetch_backend",
    "bq_dataset",
    "bq_android_table",
    "bq_ios_table",
    "jira_project_key",
    "jira_server_url",
    "jira_email",
    "jira_token",
    "jira_issue_type",
    "jira_create_fields",
    "jira_create_mode",
    "jira_parent_issue_key",
    "gitlab_project",
    "crashlytics_android_package",
    "crashlytics_ios_bundle_id",
    "google_application_credentials",
    "created_at",
    "updated_at",
    "last_selected_at",
)


def _count_rows(conn: psycopg.Connection, table: str, user_id: str) -> int:
    with conn.cursor() as cur:
        cur.execute(f"SELECT COUNT(*) FROM {table} WHERE user_id = %s", (user_id,))
        row = cur.fetchone()
        return int(row[0] if row else 0)


def _wipe_target(conn: psycopg.Connection, *, user_id: str) -> dict[str, int]:
    deleted: dict[str, int] = {}
    for table in ("repo_indexes", "repos", "app_settings", "app_state"):
        with conn.cursor() as cur:
            cur.execute(f"DELETE FROM {table} WHERE user_id = %s", (user_id,))
            deleted[table] = int(cur.rowcount or 0)
    return deleted


def _copy_repos(conn: psycopg.Connection, *, from_user: str, to_user: str) -> int:
    with conn.cursor() as cur:
        cur.execute(
            f"SELECT {', '.join(_REPO_COLUMNS)} FROM repos WHERE user_id = %s ORDER BY repo_key",
            (from_user,),
        )
        rows = cur.fetchall()
        for row in rows:
            values = {col: row[i] for i, col in enumerate(_REPO_COLUMNS)}
            cur.execute(
                f"""
                INSERT INTO repos (user_id, {', '.join(_REPO_COLUMNS)})
                VALUES (%s, {', '.join(['%s'] * len(_REPO_COLUMNS))})
                ON CONFLICT (user_id, repo_key) DO UPDATE SET
                  {', '.join(f'{c} = EXCLUDED.{c}' for c in _REPO_COLUMNS if c != 'repo_key')}
                """,
                (to_user, *[values[c] for c in _REPO_COLUMNS]),
            )
    return len(rows)


def _copy_app_settings(conn: psycopg.Connection, *, from_user: str, to_user: str) -> int:
    with conn.cursor() as cur:
        cur.execute(
            "SELECT k, v, updated_at FROM app_settings WHERE user_id = %s ORDER BY k",
            (from_user,),
        )
        rows = cur.fetchall()
        for row in rows:
            k, v, updated_at = row
            cur.execute(
                """
                INSERT INTO app_settings (user_id, k, v, updated_at)
                VALUES (%s, %s, %s, %s)
                ON CONFLICT (user_id, k) DO UPDATE SET
                  v = EXCLUDED.v,
                  updated_at = EXCLUDED.updated_at
                """,
                (to_user, k, Json(v) if v is not None else None, updated_at),
            )
    return len(rows)


def _copy_app_state(conn: psycopg.Connection, *, from_user: str, to_user: str) -> int:
    with conn.cursor() as cur:
        cur.execute(
            "SELECT k, v FROM app_state WHERE user_id = %s ORDER BY k",
            (from_user,),
        )
        rows = cur.fetchall()
        for row in rows:
            k, v = row
            cur.execute(
                """
                INSERT INTO app_state (user_id, k, v)
                VALUES (%s, %s, %s)
                ON CONFLICT (user_id, k) DO UPDATE SET v = EXCLUDED.v
                """,
                (to_user, k, v),
            )
    return len(rows)


def _copy_repo_indexes(conn: psycopg.Connection, *, from_user: str, to_user: str) -> int:
    with conn.cursor() as cur:
        cur.execute(
            """
            SELECT repo_key, indexed_sha, last_indexed_at, last_error
            FROM repo_indexes
            WHERE user_id = %s
            ORDER BY repo_key
            """,
            (from_user,),
        )
        rows = cur.fetchall()
        for row in rows:
            repo_key, indexed_sha, last_indexed_at, last_error = row
            cur.execute(
                """
                INSERT INTO repo_indexes (
                  user_id, repo_key, indexed_sha, last_indexed_at, last_error
                ) VALUES (%s, %s, %s, %s, %s)
                ON CONFLICT (user_id, repo_key) DO UPDATE SET
                  indexed_sha = EXCLUDED.indexed_sha,
                  last_indexed_at = EXCLUDED.last_indexed_at,
                  last_error = EXCLUDED.last_error
                """,
                (to_user, repo_key, indexed_sha, last_indexed_at, last_error),
            )
    return len(rows)


def _copy_all(
    conn: psycopg.Connection,
    *,
    from_user: str,
    to_user: str,
    wipe_target: bool,
) -> dict[str, Any]:
    before = {
        table: _count_rows(conn, table, to_user)
        for table in ("repos", "app_settings", "app_state", "repo_indexes")
    }
    source = {
        table: _count_rows(conn, table, from_user)
        for table in ("repos", "app_settings", "app_state", "repo_indexes")
    }

    wiped: dict[str, int] | None = None
    if wipe_target:
        wiped = _wipe_target(conn, user_id=to_user)

    copied = {
        "repos": _copy_repos(conn, from_user=from_user, to_user=to_user),
        "app_settings": _copy_app_settings(conn, from_user=from_user, to_user=to_user),
        "app_state": _copy_app_state(conn, from_user=from_user, to_user=to_user),
        "repo_indexes": _copy_repo_indexes(conn, from_user=from_user, to_user=to_user),
    }
    after = {
        table: _count_rows(conn, table, to_user)
        for table in ("repos", "app_settings", "app_state", "repo_indexes")
    }
    return {
        "source": source,
        "target_before": before,
        "target_after": after,
        "copied": copied,
        "wiped": wiped,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--from-user",
        default="cr231120",
        help="Source user id (normalized lowercase). Default: cr231120.",
    )
    parser.add_argument(
        "--to-user",
        required=True,
        help="Destination user id (normalized lowercase).",
    )
    parser.add_argument(
        "--url",
        "--crash-db-url",
        dest="url",
        default=None,
        help="Postgres URL (default: AI_CRASH_FIX_CRASH_DB_URL from env/.env).",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Report row counts only; do not write.",
    )
    parser.add_argument(
        "--wipe-target",
        action="store_true",
        help="Delete existing target user rows in repos/settings/state/indexes before copy.",
    )
    args = parser.parse_args()

    from_user = normalize_user_id(args.from_user)
    to_user = normalize_user_id(args.to_user)
    if not from_user:
        print("--from-user is required", file=sys.stderr)
        return 2
    if not to_user:
        print("--to-user is required", file=sys.stderr)
        return 2
    if from_user == to_user:
        print("from-user and to-user must differ", file=sys.stderr)
        return 2

    from app.config import AI_CRASH_FIX_CRASH_DB_URL

    url = (args.url or AI_CRASH_FIX_CRASH_DB_URL or os.getenv("AI_CRASH_FIX_CRASH_DB_URL") or "").strip()
    if not url:
        print("AI_CRASH_FIX_CRASH_DB_URL or --url is required", file=sys.stderr)
        return 2

    with psycopg.connect(url) as conn:
        ensure_app_postgres_schema(conn)
        source = {
            table: _count_rows(conn, table, from_user)
            for table in ("repos", "app_settings", "app_state", "repo_indexes")
        }
        target_before = {
            table: _count_rows(conn, table, to_user)
            for table in ("repos", "app_settings", "app_state", "repo_indexes")
        }

        print(f"from_user={from_user}")
        print(f"to_user={to_user}")
        print("source " + " ".join(f"{k}={v}" for k, v in source.items()))
        print("target_before " + " ".join(f"{k}={v}" for k, v in target_before.items()))

        if sum(source.values()) == 0:
            print(f"warning: source user {from_user!r} has no repo data to copy", file=sys.stderr)

        if args.dry_run:
            print("dry_run=1 (no writes)")
            return 0

        result = _copy_all(
            conn,
            from_user=from_user,
            to_user=to_user,
            wipe_target=args.wipe_target,
        )
        conn.commit()

    print("copied " + " ".join(f"{k}={v}" for k, v in result["copied"].items()))
    if result["wiped"] is not None:
        print("wiped " + " ".join(f"{k}={v}" for k, v in result["wiped"].items()))
    print("target_after " + " ".join(f"{k}={v}" for k, v in result["target_after"].items()))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
