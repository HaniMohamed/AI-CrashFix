#!/usr/bin/env python3
"""
Delete crash-store rows from the last N days so they can be re-processed.

Supports:
  - SQLite crash DB files (default for local / macOS app)
  - Postgres when AI_CRASH_FIX_CRASH_STORE_BACKEND=postgres

Dry-run by default; pass --apply to delete.

Examples:
  # Preview SQLite (last 2 days by created_at)
  python scripts/delete_recent_crashes.py \\
    --db "$HOME/Library/Application Support/Fixora/db/<project>_<repo>_crash_store.db"

  # Delete last 2 days from that SQLite DB
  python scripts/delete_recent_crashes.py --db "<path>" --apply

  # Postgres (uses AI_CRASH_FIX_CRASH_DB_URL from env / .env)
  python scripts/delete_recent_crashes.py --postgres --apply

  # Only one Firebase project in Postgres
  python scripts/delete_recent_crashes.py --postgres --project-id taminaty-2e06a --apply

  # Match on updated_at instead of created_at; custom window
  python scripts/delete_recent_crashes.py --db "<path>" --days 2 --by updated_at --apply
"""

from __future__ import annotations

import argparse
import os
import sqlite3
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path


def _cutoff(*, days: float) -> datetime:
    return datetime.now(timezone.utc) - timedelta(days=days)


def _cutoff_iso(cutoff: datetime) -> str:
    # SQLite stores naive/aware ISO strings from datetime.utcnow().isoformat()
    # and CURRENT_TIMESTAMP. Compare as text against ISO-8601 UTC.
    return cutoff.astimezone(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def _list_sqlite_matches(
    conn: sqlite3.Connection, *, cutoff_iso: str, by: str
) -> list[sqlite3.Row]:
    col = "created_at" if by == "created_at" else "updated_at"
    # datetime() handles most ISO / SQLite timestamp shapes.
    return list(
        conn.execute(
            f"""
            SELECT crash_id, status, created_at, updated_at
            FROM crashes
            WHERE datetime(replace(replace({col}, 'T', ' '), 'Z', ''))
                  >= datetime(replace(replace(?, 'T', ' '), 'Z', ''))
            ORDER BY datetime(replace(replace({col}, 'T', ' '), 'Z', '')) DESC
            """,
            (cutoff_iso,),
        ).fetchall()
    )


def _delete_sqlite(conn: sqlite3.Connection, *, cutoff_iso: str, by: str) -> int:
    col = "created_at" if by == "created_at" else "updated_at"
    cur = conn.execute(
        f"""
        DELETE FROM crashes
        WHERE datetime(replace(replace({col}, 'T', ' '), 'Z', ''))
              >= datetime(replace(replace(?, 'T', ' '), 'Z', ''))
        """,
        (cutoff_iso,),
    )
    conn.commit()
    return int(cur.rowcount or 0)


def _list_postgres_matches(
    conn,
    *,
    cutoff: datetime,
    by: str,
    project_id: str | None,
) -> list[dict]:
    col = "created_at" if by == "created_at" else "updated_at"
    sql = f"""
        SELECT firebase_project_id, crash_id, status, created_at, updated_at
        FROM crashes
        WHERE {col} >= %s
    """
    params: list[object] = [cutoff]
    if project_id:
        sql += " AND firebase_project_id = %s"
        params.append(project_id)
    sql += f" ORDER BY {col} DESC"
    with conn.cursor() as cur:
        cur.execute(sql, params)
        rows = cur.fetchall()
    return list(rows)


def _delete_postgres(
    conn,
    *,
    cutoff: datetime,
    by: str,
    project_id: str | None,
) -> int:
    col = "created_at" if by == "created_at" else "updated_at"
    sql = f"DELETE FROM crashes WHERE {col} >= %s"
    params: list[object] = [cutoff]
    if project_id:
        sql += " AND firebase_project_id = %s"
        params.append(project_id)
    with conn.cursor() as cur:
        cur.execute(sql, params)
        n = cur.rowcount
    conn.commit()
    return int(n or 0)


def _print_sqlite_rows(rows: list[sqlite3.Row]) -> None:
    for r in rows:
        print(
            f"  {r['crash_id']}\tstatus={r['status']}\t"
            f"created={r['created_at']}\tupdated={r['updated_at']}"
        )


def _print_pg_rows(rows: list[dict]) -> None:
    for r in rows:
        print(
            f"  [{r.get('firebase_project_id')}] {r.get('crash_id')}\t"
            f"status={r.get('status')}\t"
            f"created={r.get('created_at')}\tupdated={r.get('updated_at')}"
        )


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Delete crash-store rows from the last N days (dry-run unless --apply)."
    )
    parser.add_argument(
        "--days",
        type=float,
        default=2.0,
        help="Delete rows with created_at/updated_at within this many days (default: 2).",
    )
    parser.add_argument(
        "--by",
        choices=("created_at", "updated_at"),
        default="created_at",
        help="Timestamp column to filter on (default: created_at).",
    )
    parser.add_argument(
        "--db",
        type=str,
        default=None,
        help="SQLite crash store path (*.db).",
    )
    parser.add_argument(
        "--postgres",
        action="store_true",
        help="Use Postgres (AI_CRASH_FIX_CRASH_DB_URL or --db-url).",
    )
    parser.add_argument(
        "--db-url",
        type=str,
        default=None,
        help="Postgres URL override (else AI_CRASH_FIX_CRASH_DB_URL).",
    )
    parser.add_argument(
        "--project-id",
        type=str,
        default=None,
        help="Postgres only: limit to this firebase_project_id.",
    )
    parser.add_argument(
        "--apply",
        action="store_true",
        help="Actually delete. Without this flag, only list matching rows.",
    )
    args = parser.parse_args(argv)

    if args.days <= 0:
        print("--days must be > 0", file=sys.stderr)
        return 2

    cutoff = _cutoff(days=args.days)
    cutoff_iso = _cutoff_iso(cutoff)
    mode = "DELETE" if args.apply else "DRY-RUN"
    print(
        f"[{mode}] removing crashes with {args.by} >= {cutoff_iso} "
        f"(last {args.days:g} day(s))"
    )

    if args.postgres or args.db_url:
        url = (args.db_url or os.environ.get("AI_CRASH_FIX_CRASH_DB_URL") or "").strip()
        if not url:
            # Late import so SQLite-only users need no psycopg.
            try:
                from app.config import AI_CRASH_FIX_CRASH_DB_URL as cfg_url
            except Exception:
                cfg_url = None
            url = (cfg_url or "").strip()
        if not url:
            print(
                "Missing Postgres URL. Set AI_CRASH_FIX_CRASH_DB_URL or pass --db-url.",
                file=sys.stderr,
            )
            return 2
        try:
            import psycopg
            from psycopg.rows import dict_row
        except ImportError:
            print("psycopg is required for --postgres. Install project deps.", file=sys.stderr)
            return 2

        with psycopg.connect(url, row_factory=dict_row) as conn:
            rows = _list_postgres_matches(
                conn,
                cutoff=cutoff,
                by=args.by,
                project_id=(args.project_id or "").strip() or None,
            )
            print(f"Matched {len(rows)} row(s).")
            _print_pg_rows(rows[:50])
            if len(rows) > 50:
                print(f"  … and {len(rows) - 50} more")
            if not args.apply:
                print("\nNo changes. Re-run with --apply to delete.")
                return 0
            if not rows:
                return 0
            deleted = _delete_postgres(
                conn,
                cutoff=cutoff,
                by=args.by,
                project_id=(args.project_id or "").strip() or None,
            )
            print(f"Deleted {deleted} row(s).")
        return 0

    db_path = (args.db or "").strip()
    if not db_path:
        print("Pass --db <sqlite-path> or --postgres.", file=sys.stderr)
        return 2
    path = Path(db_path).expanduser().resolve()
    if not path.is_file():
        print(f"SQLite file not found: {path}", file=sys.stderr)
        return 2

    conn = sqlite3.connect(str(path), timeout=30.0)
    conn.row_factory = sqlite3.Row
    try:
        rows = _list_sqlite_matches(conn, cutoff_iso=cutoff_iso, by=args.by)
        print(f"DB: {path}")
        print(f"Matched {len(rows)} row(s).")
        _print_sqlite_rows(rows[:50])
        if len(rows) > 50:
            print(f"  … and {len(rows) - 50} more")
        if not args.apply:
            print("\nNo changes. Re-run with --apply to delete.")
            return 0
        if not rows:
            return 0
        deleted = _delete_sqlite(conn, cutoff_iso=cutoff_iso, by=args.by)
        print(f"Deleted {deleted} row(s).")
    finally:
        conn.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
