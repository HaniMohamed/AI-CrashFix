#!/usr/bin/env python3
"""One-time import of local SQLite crash stores into shared Postgres.

Scans ``db/*_crash_store.db`` (and optional ``AI_CRASH_FIX_DATA_DIR``). Does not
delete or modify source SQLite files. When the same ``crash_id`` appears in
multiple repo-scoped files for one Firebase project, keeps the row with the
latest ``updated_at``; ties break on higher ``pipeline_complete``.
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

import psycopg
from psycopg.types.json import Json

from app.services.crash_store_common import PIPELINE_FLAG_COLUMNS
from app.services.crash_store_postgres import ensure_postgres_schema

_SUFFIX = "_crash_store.db"


@dataclass(frozen=True)
class SourceRow:
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


def _parse_project_id_from_filename(name: str) -> str | None:
    if not name.endswith(_SUFFIX):
        return None
    stem = name[: -len(_SUFFIX)]
    if not stem:
        return None
    if "_" in stem:
        return stem.split("_", 1)[0]
    return stem


def _iter_sqlite_files(*, data_dir: Path | None) -> Iterator[Path]:
    seen: set[Path] = set()
    for base in (PROJECT_ROOT / "db",):
        if base.is_dir():
            for path in sorted(base.glob(f"*{_SUFFIX}")):
                resolved = path.resolve()
                if resolved not in seen:
                    seen.add(resolved)
                    yield resolved
    if data_dir is not None:
        db_dir = data_dir / "db"
        if db_dir.is_dir():
            for path in sorted(db_dir.glob(f"*{_SUFFIX}")):
                resolved = path.resolve()
                if resolved not in seen:
                    seen.add(resolved)
                    yield resolved
        for path in sorted(data_dir.glob(f"*{_SUFFIX}")):
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


def _row_rank(row: SourceRow) -> tuple[datetime, int]:
    updated = _parse_iso(row.updated_at) or datetime.min
    complete = 1 if row.flags.get("pipeline_complete") else 0
    return (updated, complete)


def _load_sqlite_rows(path: Path, firebase_project_id: str) -> list[SourceRow]:
    out: list[SourceRow] = []
    with sqlite3.connect(path) as conn:
        conn.row_factory = sqlite3.Row
        cols = (
            "crash_id",
            "jira_issue_id",
            "pr_url",
            "status",
            "created_at",
            "updated_at",
            "result",
            *PIPELINE_FLAG_COLUMNS,
        )
        rows = conn.execute(f"SELECT {', '.join(cols)} FROM crashes").fetchall()
    for row in rows:
        flags = {col: bool(row[col]) for col in PIPELINE_FLAG_COLUMNS}
        raw_result = row["result"]
        parsed: dict | None = None
        if raw_result:
            try:
                parsed = json.loads(raw_result)
            except Exception:
                parsed = None
        out.append(
            SourceRow(
                firebase_project_id=firebase_project_id,
                crash_id=str(row["crash_id"]),
                jira_issue_id=row["jira_issue_id"],
                pr_url=row["pr_url"],
                status=row["status"],
                created_at=row["created_at"],
                updated_at=row["updated_at"],
                result=parsed,
                flags=flags,
                source_db=str(path),
            )
        )
    return out


def _merge_rows(rows: list[SourceRow]) -> dict[tuple[str, str], SourceRow]:
    merged: dict[tuple[str, str], SourceRow] = {}
    for row in rows:
        key = (row.firebase_project_id, row.crash_id)
        existing = merged.get(key)
        if existing is None or _row_rank(row) >= _row_rank(existing):
            merged[key] = row
    return merged


def _upsert_row(conn: psycopg.Connection, row: SourceRow) -> None:
    with conn.cursor() as cur:
        cur.execute(
            """
            INSERT INTO crashes (
              firebase_project_id,
              crash_id,
              jira_issue_id,
              pr_url,
              status,
              created_at,
              updated_at,
              result,
              analysis_done,
              jira_created,
              fix_generated,
              fix_validated,
              diff_applied,
              branch_created,
              mr_created,
              pipeline_complete
            ) VALUES (
              %s, %s, %s, %s, %s, %s, %s, %s,
              %s, %s, %s, %s, %s, %s, %s, %s
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
              pipeline_complete = EXCLUDED.pipeline_complete
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
                row.flags["analysis_done"],
                row.flags["jira_created"],
                row.flags["fix_generated"],
                row.flags["fix_validated"],
                row.flags["diff_applied"],
                row.flags["branch_created"],
                row.flags["mr_created"],
                row.flags["pipeline_complete"],
            ),
        )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Scan and merge only; do not write to Postgres.",
    )
    parser.add_argument(
        "--crash-db-url",
        default=(os.getenv("AI_CRASH_FIX_CRASH_DB_URL") or "").strip() or None,
        help="Postgres URL (default: AI_CRASH_FIX_CRASH_DB_URL).",
    )
    args = parser.parse_args()

    data_dir_raw = (os.getenv("AI_CRASH_FIX_DATA_DIR") or "").strip()
    data_dir = Path(data_dir_raw).expanduser().resolve() if data_dir_raw else None

    collected: list[SourceRow] = []
    for path in _iter_sqlite_files(data_dir=data_dir):
        project_id = _parse_project_id_from_filename(path.name)
        if not project_id:
            print(f"skip {path}: could not parse firebase project id", file=sys.stderr)
            continue
        collected.extend(_load_sqlite_rows(path, project_id))

    merged = _merge_rows(collected)
    print(f"scanned_rows={len(collected)} merged_rows={len(merged)} sqlite_files={len(set(r.source_db for r in collected))}")

    if args.dry_run:
        return 0

    url = (args.crash_db_url or "").strip()
    if not url:
        print("AI_CRASH_FIX_CRASH_DB_URL or --crash-db-url is required", file=sys.stderr)
        return 2

    with psycopg.connect(url) as conn:
        ensure_postgres_schema(conn)
        for row in merged.values():
            _upsert_row(conn, row)
        conn.commit()

    print(f"imported_rows={len(merged)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
