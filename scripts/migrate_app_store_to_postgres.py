#!/usr/bin/env python3
"""Import local SQLite app + crash stores into shared Postgres under a user id.

Reads Application Support / data-dir SQLite files without deleting them.
User ids are normalized to lowercase.

Example:

  python scripts/migrate_app_store_to_postgres.py \\
    --user-id cr231120 \\
    --data-dir "/Users/hanihussein/Library/Application Support/AI Crash Fix" \\
    --url "$AI_CRASH_FIX_CRASH_DB_URL"
"""

from __future__ import annotations

import argparse
import json
import os
import sqlite3
import sys
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Any, Iterator

PROJECT_ROOT = Path(__file__).resolve().parents[1]
if str(PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(PROJECT_ROOT))

# Load .env so AI_CRASH_FIX_CRASH_DB_URL / USER_ID are available without --url.
from app import config as _cfg  # noqa: F401

import psycopg
from psycopg.types.json import Json

from app.services.crash_store_common import PIPELINE_FLAG_COLUMNS
from app.services.postgres_schema import ensure_app_postgres_schema
from app.services.user_context import normalize_user_id

_SUFFIX = "_crash_store.db"

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
    "created_at",
    "updated_at",
    "last_selected_at",
)


@dataclass(frozen=True)
class SourceCrash:
    firebase_project_id: str
    crash_id: str
    jira_issue_id: str | None
    pr_url: str | None
    status: str | None
    created_at: str | None
    updated_at: str | None
    result: dict | None
    flags: dict[str, bool]
    source_db: str


def _checkpoint(conn: sqlite3.Connection) -> None:
    try:
        conn.execute("PRAGMA wal_checkpoint(FULL)")
    except sqlite3.Error:
        pass


def _open_sqlite(path: Path) -> sqlite3.Connection:
    conn = sqlite3.connect(str(path), timeout=60.0)
    conn.row_factory = sqlite3.Row
    _checkpoint(conn)
    return conn


def _table_cols(conn: sqlite3.Connection, table: str) -> set[str]:
    rows = conn.execute(f"PRAGMA table_info({table})").fetchall()
    return {str(r[1]) for r in rows}


def _parse_project_id_from_filename(name: str) -> str | None:
    if not name.endswith(_SUFFIX):
        return None
    stem = name[: -len(_SUFFIX)]
    if not stem:
        return None
    if "_" in stem:
        return stem.split("_", 1)[0]
    return stem


def _iter_crash_sqlite_files(data_dir: Path) -> Iterator[Path]:
    seen: set[Path] = set()
    for base in (data_dir / "db", data_dir):
        if not base.is_dir():
            continue
        for path in sorted(base.glob(f"*{_SUFFIX}")):
            resolved = path.resolve()
            if resolved not in seen:
                seen.add(resolved)
                yield resolved


def _parse_iso(value: Any) -> datetime | None:
    if not value or not isinstance(value, str):
        return None
    try:
        return datetime.fromisoformat(value)
    except Exception:
        return None


def _crash_rank(row: SourceCrash) -> tuple[datetime, int]:
    updated = _parse_iso(row.updated_at) or datetime.min
    complete = 1 if row.flags.get("pipeline_complete") else 0
    return (updated, complete)


def _load_crashes(path: Path, firebase_project_id: str) -> list[SourceCrash]:
    out: list[SourceCrash] = []
    with _open_sqlite(path) as conn:
        existing = _table_cols(conn, "crashes")
        if "crash_id" not in existing:
            return out
        cols = [
            c
            for c in (
                "crash_id",
                "jira_issue_id",
                "pr_url",
                "status",
                "created_at",
                "updated_at",
                "result",
                *PIPELINE_FLAG_COLUMNS,
            )
            if c in existing or c in PIPELINE_FLAG_COLUMNS
        ]
        # Only select columns that exist.
        cols = [c for c in cols if c in existing]
        rows = conn.execute(f"SELECT {', '.join(cols)} FROM crashes").fetchall()
    for row in rows:
        flags = {col: bool(row[col]) if col in row.keys() else False for col in PIPELINE_FLAG_COLUMNS}
        raw_result = row["result"] if "result" in row.keys() else None
        parsed: dict | None = None
        if raw_result:
            try:
                parsed = json.loads(raw_result)
            except Exception:
                parsed = None
        out.append(
            SourceCrash(
                firebase_project_id=firebase_project_id,
                crash_id=str(row["crash_id"]),
                jira_issue_id=row["jira_issue_id"] if "jira_issue_id" in row.keys() else None,
                pr_url=row["pr_url"] if "pr_url" in row.keys() else None,
                status=row["status"] if "status" in row.keys() else None,
                created_at=row["created_at"] if "created_at" in row.keys() else None,
                updated_at=row["updated_at"] if "updated_at" in row.keys() else None,
                result=parsed,
                flags=flags,
                source_db=str(path),
            )
        )
    return out


def _merge_crashes(rows: list[SourceCrash]) -> dict[tuple[str, str], SourceCrash]:
    merged: dict[tuple[str, str], SourceCrash] = {}
    for row in rows:
        key = (row.firebase_project_id, row.crash_id)
        existing = merged.get(key)
        if existing is None or _crash_rank(row) >= _crash_rank(existing):
            merged[key] = row
    return merged


def _upsert_crash(conn: psycopg.Connection, row: SourceCrash, *, user_id: str) -> None:
    with conn.cursor() as cur:
        cur.execute(
            """
            INSERT INTO crashes (
              firebase_project_id, crash_id, jira_issue_id, pr_url, status,
              created_at, updated_at, result,
              analysis_done, jira_created, fix_generated, fix_validated,
              diff_applied, branch_created, mr_created, pipeline_complete,
              created_by_user_id
            ) VALUES (
              %s, %s, %s, %s, %s, %s, %s, %s,
              %s, %s, %s, %s, %s, %s, %s, %s, %s
            )
            ON CONFLICT (firebase_project_id, crash_id) DO UPDATE SET
              jira_issue_id = EXCLUDED.jira_issue_id,
              pr_url = EXCLUDED.pr_url,
              status = EXCLUDED.status,
              created_at = EXCLUDED.created_at,
              updated_at = EXCLUDED.updated_at,
              result = EXCLUDED.result,
              analysis_done = EXCLUDED.analysis_done,
              jira_created = EXCLUDED.jira_created,
              fix_generated = EXCLUDED.fix_generated,
              fix_validated = EXCLUDED.fix_validated,
              diff_applied = EXCLUDED.diff_applied,
              branch_created = EXCLUDED.branch_created,
              mr_created = EXCLUDED.mr_created,
              pipeline_complete = EXCLUDED.pipeline_complete,
              created_by_user_id = COALESCE(crashes.created_by_user_id, EXCLUDED.created_by_user_id)
            """,
            (
                row.firebase_project_id,
                row.crash_id,
                row.jira_issue_id,
                row.pr_url,
                row.status or "in_progress",
                row.created_at,
                row.updated_at,
                Json(row.result) if row.result is not None else None,
                row.flags.get("analysis_done", False),
                row.flags.get("jira_created", False),
                row.flags.get("fix_generated", False),
                row.flags.get("fix_validated", False),
                row.flags.get("diff_applied", False),
                row.flags.get("branch_created", False),
                row.flags.get("mr_created", False),
                row.flags.get("pipeline_complete", False),
                user_id,
            ),
        )


def _import_registry(conn: psycopg.Connection, registry_db: Path, *, user_id: str, dry_run: bool) -> dict[str, int]:
    counts = {"repos": 0, "app_settings": 0, "app_state": 0, "repo_indexes": 0}
    if not registry_db.is_file():
        print(f"registry missing: {registry_db}", file=sys.stderr)
        return counts

    with _open_sqlite(registry_db) as sqlite_conn:
        tables = {
            r[0]
            for r in sqlite_conn.execute(
                "SELECT name FROM sqlite_master WHERE type='table'"
            ).fetchall()
        }

        if "repos" in tables:
            existing = _table_cols(sqlite_conn, "repos")
            cols = [c for c in _REPO_COLUMNS if c in existing]
            rows = sqlite_conn.execute(f"SELECT {', '.join(cols)} FROM repos").fetchall()
            counts["repos"] = len(rows)
            if not dry_run:
                with conn.cursor() as cur:
                    for row in rows:
                        values = {c: row[c] if c in row.keys() else None for c in _REPO_COLUMNS}
                        cur.execute(
                            f"""
                            INSERT INTO repos (user_id, {', '.join(_REPO_COLUMNS)})
                            VALUES (%s, {', '.join(['%s'] * len(_REPO_COLUMNS))})
                            ON CONFLICT (user_id, repo_key) DO UPDATE SET
                              {', '.join(f'{c} = EXCLUDED.{c}' for c in _REPO_COLUMNS if c != 'repo_key')}
                            """,
                            (user_id, *[values[c] for c in _REPO_COLUMNS]),
                        )

        if "app_settings" in tables:
            rows = sqlite_conn.execute("SELECT k, v, updated_at FROM app_settings").fetchall()
            counts["app_settings"] = len(rows)
            if not dry_run:
                with conn.cursor() as cur:
                    for row in rows:
                        k = str(row["k"] or "").strip()
                        if not k:
                            continue
                        raw = row["v"]
                        parsed: Any = None
                        if raw is not None:
                            try:
                                parsed = json.loads(str(raw))
                            except Exception:
                                parsed = str(raw)
                        cur.execute(
                            """
                            INSERT INTO app_settings (user_id, k, v, updated_at)
                            VALUES (%s, %s, %s, %s)
                            ON CONFLICT (user_id, k) DO UPDATE SET
                              v = EXCLUDED.v,
                              updated_at = EXCLUDED.updated_at
                            """,
                            (user_id, k, Json(parsed), row["updated_at"]),
                        )

        if "app_state" in tables:
            rows = sqlite_conn.execute("SELECT k, v FROM app_state").fetchall()
            counts["app_state"] = len(rows)
            if not dry_run:
                with conn.cursor() as cur:
                    for row in rows:
                        k = str(row["k"] or "").strip()
                        if not k:
                            continue
                        cur.execute(
                            """
                            INSERT INTO app_state (user_id, k, v)
                            VALUES (%s, %s, %s)
                            ON CONFLICT (user_id, k) DO UPDATE SET v = EXCLUDED.v
                            """,
                            (user_id, k, row["v"]),
                        )

        if "repo_indexes" in tables:
            rows = sqlite_conn.execute(
                "SELECT repo_key, indexed_sha, last_indexed_at, last_error FROM repo_indexes"
            ).fetchall()
            counts["repo_indexes"] = len(rows)
            if not dry_run:
                with conn.cursor() as cur:
                    for row in rows:
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
                            (
                                user_id,
                                row["repo_key"],
                                row["indexed_sha"],
                                row["last_indexed_at"],
                                row["last_error"],
                            ),
                        )

    return counts


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dry-run", action="store_true", help="Scan only; do not write.")
    parser.add_argument(
        "--user-id",
        default=(os.getenv("AI_CRASH_FIX_USER_ID") or "").strip() or None,
        help="Owner user id (normalized lowercase). Default: AI_CRASH_FIX_USER_ID.",
    )
    parser.add_argument(
        "--data-dir",
        default=(os.getenv("AI_CRASH_FIX_DATA_DIR") or "").strip() or None,
        help="App data dir containing db/repo_registry.db and *_crash_store.db",
    )
    parser.add_argument(
        "--url",
        "--crash-db-url",
        dest="url",
        default=None,
        help="Postgres URL (default: AI_CRASH_FIX_CRASH_DB_URL from env/.env).",
    )
    args = parser.parse_args()

    user_id = normalize_user_id(args.user_id)
    if not user_id:
        print("--user-id or AI_CRASH_FIX_USER_ID is required", file=sys.stderr)
        return 2

    if not args.data_dir:
        print("--data-dir or AI_CRASH_FIX_DATA_DIR is required", file=sys.stderr)
        return 2
    data_dir = Path(args.data_dir).expanduser().resolve()
    if not data_dir.is_dir():
        print(f"data-dir not found: {data_dir}", file=sys.stderr)
        return 2

    registry_db = data_dir / "db" / "repo_registry.db"
    if not registry_db.is_file():
        # Fallback: registry at data_dir root
        alt = data_dir / "repo_registry.db"
        if alt.is_file():
            registry_db = alt

    collected: list[SourceCrash] = []
    for path in _iter_crash_sqlite_files(data_dir):
        project_id = _parse_project_id_from_filename(path.name)
        if not project_id:
            print(f"skip {path}: could not parse firebase project id", file=sys.stderr)
            continue
        collected.extend(_load_crashes(path, project_id))
    merged = _merge_crashes(collected)

    print(f"user_id={user_id}")
    print(f"data_dir={data_dir}")
    print(f"registry_db={registry_db} exists={registry_db.is_file()}")
    print(
        f"crash_scanned={len(collected)} crash_merged={len(merged)} "
        f"crash_files={len({r.source_db for r in collected})}"
    )

    if args.dry_run:
        # Still report registry counts without writing.
        if registry_db.is_file():
            with _open_sqlite(registry_db) as sqlite_conn:
                tables = {
                    r[0]
                    for r in sqlite_conn.execute(
                        "SELECT name FROM sqlite_master WHERE type='table'"
                    ).fetchall()
                }
                for t in ("repos", "app_settings", "app_state", "repo_indexes"):
                    if t in tables:
                        n = sqlite_conn.execute(f"SELECT COUNT(*) FROM {t}").fetchone()[0]
                        print(f"dry_run {t}={n}")
        print("dry_run=1 (no writes)")
        return 0

    from app.config import AI_CRASH_FIX_CRASH_DB_URL

    url = (args.url or AI_CRASH_FIX_CRASH_DB_URL or os.getenv("AI_CRASH_FIX_CRASH_DB_URL") or "").strip()
    if not url:
        print("AI_CRASH_FIX_CRASH_DB_URL or --url is required", file=sys.stderr)
        return 2

    with psycopg.connect(url) as conn:
        ensure_app_postgres_schema(conn)
        counts = _import_registry(conn, registry_db, user_id=user_id, dry_run=False)
        for row in merged.values():
            _upsert_crash(conn, row, user_id=user_id)
        conn.commit()

    print(
        "imported "
        + " ".join(f"{k}={v}" for k, v in counts.items())
        + f" crashes={len(merged)}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
