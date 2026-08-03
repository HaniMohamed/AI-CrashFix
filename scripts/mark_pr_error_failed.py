#!/usr/bin/env python3
"""
Find crash rows whose stored `result` JSON has a non-empty `pr_error`, and mark them
failed so they can be re-run from the UI (Re-run requires status == failed).

Usage:
  # Preview matches (default)
  python scripts/mark_pr_error_failed.py \\
    --db "/Users/hanihussein/Library/Application Support/Fixora/db/taminaty-2e06a_64759a75c5be_crash_store.db"

  # Apply updates
  python scripts/mark_pr_error_failed.py --db "<path>" --apply
"""

from __future__ import annotations

import argparse
import json
import sqlite3
import sys
from datetime import datetime, timezone
from pathlib import Path


def _connect(db_path: Path) -> sqlite3.Connection:
    conn = sqlite3.connect(str(db_path), timeout=30.0)
    conn.row_factory = sqlite3.Row
    return conn


def _pr_error_from_row(row: sqlite3.Row) -> str | None:
    raw = row["result"]
    if not raw:
        return None
    try:
        data = json.loads(raw) if isinstance(raw, str) else raw
    except json.JSONDecodeError:
        return None
    if not isinstance(data, dict):
        return None
    err = data.get("pr_error")
    if err is None:
        return None
    text = str(err).strip()
    return text or None


def find_pr_error_rows(conn: sqlite3.Connection) -> list[sqlite3.Row]:
    rows = conn.execute(
        """
        SELECT crash_id, status, pipeline_complete, result
        FROM crashes
        WHERE result IS NOT NULL
          AND trim(result) != ''
          AND COALESCE(NULLIF(trim(json_extract(result, '$.pr_error')), ''), NULL) IS NOT NULL
        ORDER BY datetime(updated_at) DESC
        """
    ).fetchall()
    # Double-check in Python (handles edge cases json_extract might miss).
    out: list[sqlite3.Row] = []
    for row in rows:
        if _pr_error_from_row(row):
            out.append(row)
    return out


def mark_failed(conn: sqlite3.Connection, crash_ids: list[str], *, apply: bool) -> int:
    if not crash_ids:
        return 0
    now = datetime.now(timezone.utc).replace(microsecond=0).isoformat()
    if not apply:
        return len(crash_ids)
    with conn:
        conn.executemany(
            """
            UPDATE crashes
            SET status = 'failed',
                pipeline_complete = 0,
                updated_at = ?
            WHERE crash_id = ?
            """,
            [(now, cid) for cid in crash_ids],
        )
    return len(crash_ids)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--db",
        required=True,
        help="Path to *_crash_store.db (SQLite)",
    )
    parser.add_argument(
        "--apply",
        action="store_true",
        help="Write status=failed and pipeline_complete=0 (default is dry-run)",
    )
    args = parser.parse_args()

    db_path = Path(args.db).expanduser()
    if not db_path.is_file():
        print(f"Database not found: {db_path}", file=sys.stderr)
        return 1

    conn = _connect(db_path)
    try:
        rows = find_pr_error_rows(conn)
        if not rows:
            print("No rows with a non-empty result.pr_error.")
            return 0

        to_update: list[str] = []
        print(f"Found {len(rows)} row(s) with pr_error:\n")
        for row in rows:
            pr_err = _pr_error_from_row(row) or ""
            preview = pr_err.replace("\n", " ")[:120]
            if len(pr_err) > 120:
                preview += "…"
            status = row["status"]
            complete = bool(row["pipeline_complete"])
            needs = status != "failed" or complete
            flag = "UPDATE" if needs else "ok"
            print(f"  [{flag}] {row['crash_id']}")
            print(f"        status={status!r} pipeline_complete={int(complete)}")
            print(f"        pr_error: {preview}")
            if needs:
                to_update.append(row["crash_id"])
            print()

        if not to_update:
            print("All matching rows are already status=failed and pipeline_complete=0.")
            return 0

        mode = "APPLY" if args.apply else "DRY-RUN"
        print(f"{mode}: would mark {len(to_update)} row(s) as failed.\n")

        if not args.apply:
            print("Re-run with --apply to write changes.")
            return 0

        n = mark_failed(conn, to_update, apply=True)
        print(f"Updated {n} row(s).")
        return 0
    finally:
        conn.close()


if __name__ == "__main__":
    raise SystemExit(main())
