from __future__ import annotations

from datetime import datetime, timezone
from typing import Any

from app.services.crash_store import uses_postgres_crash_store


def add_message(
    crash_id: str,
    role: str,
    message: str,
    *,
    status: str | None = None,
    iteration: int = 0,
    db_path: str | None = None,
    repo_key: str | None = None,
    project_id: str | None = None,
) -> None:
    if uses_postgres_crash_store():
        _add_message_postgres(
            crash_id, role, message, status=status, iteration=iteration, project_id=project_id
        )
    else:
        _add_message_sqlite(
            crash_id, role, message, status=status, iteration=iteration,
            db_path=db_path, repo_key=repo_key, project_id=project_id,
        )


def list_messages(
    crash_id: str,
    *,
    db_path: str | None = None,
    repo_key: str | None = None,
    project_id: str | None = None,
) -> list[dict[str, Any]]:
    if uses_postgres_crash_store():
        return _list_messages_postgres(crash_id, project_id=project_id)
    return _list_messages_sqlite(crash_id, db_path=db_path, repo_key=repo_key, project_id=project_id)


# -----------------------------
# SQLite backend
# -----------------------------

def _sqlite_db_path(*, db_path: str | None, repo_key: str | None, project_id: str | None) -> str:
    # Reuses the same resolution logic as SqliteCrashStore so feedback rows
    # live in the same on-disk database as the crash row they reference.
    from app.services.crash_store_sqlite import SqliteCrashStore

    return SqliteCrashStore(db_path=db_path, repo_key=repo_key, project_id=project_id).db_path


def _add_message_sqlite(
    crash_id: str,
    role: str,
    message: str,
    *,
    status: str | None,
    iteration: int,
    db_path: str | None,
    repo_key: str | None,
    project_id: str | None,
) -> None:
    from app.services.sqlite_util import connect_sqlite

    path = _sqlite_db_path(db_path=db_path, repo_key=repo_key, project_id=project_id)
    now = datetime.now(timezone.utc).isoformat()
    with connect_sqlite(path) as conn:
        conn.execute(
            """
            INSERT INTO crash_feedback (crash_id, role, message, status, iteration, created_at)
            VALUES (?, ?, ?, ?, ?, ?)
            """,
            (crash_id, role, message, status, iteration, now),
        )
        conn.commit()


def _list_messages_sqlite(
    crash_id: str,
    *,
    db_path: str | None,
    repo_key: str | None,
    project_id: str | None,
) -> list[dict[str, Any]]:
    import sqlite3

    from app.services.sqlite_util import connect_sqlite

    path = _sqlite_db_path(db_path=db_path, repo_key=repo_key, project_id=project_id)
    with connect_sqlite(path) as conn:
        conn.row_factory = sqlite3.Row
        rows = conn.execute(
            """
            SELECT id, crash_id, role, message, status, iteration, created_at
            FROM crash_feedback WHERE crash_id = ? ORDER BY id ASC
            """,
            (crash_id,),
        ).fetchall()
    return [dict(r) for r in rows]


# -----------------------------
# Postgres backend
# -----------------------------

def _postgres_project_id(project_id: str | None) -> str:
    from app.config import BQ_PROJECT_ID

    return (project_id or "").strip() or (BQ_PROJECT_ID or "").strip() or "default"


def _add_message_postgres(
    crash_id: str,
    role: str,
    message: str,
    *,
    status: str | None,
    iteration: int,
    project_id: str | None,
) -> None:
    from app.services.crash_store_postgres import _crash_db_url
    from app.services.postgres_schema import connect_postgres, ensure_app_postgres_schema

    pid = _postgres_project_id(project_id)
    with connect_postgres(_crash_db_url()) as conn:
        ensure_app_postgres_schema(conn)
        with conn.cursor() as cur:
            cur.execute(
                """
                INSERT INTO crash_feedback (firebase_project_id, crash_id, role, message, status, iteration)
                VALUES (%s, %s, %s, %s, %s, %s)
                """,
                (pid, crash_id, role, message, status, iteration),
            )
        conn.commit()


def _list_messages_postgres(crash_id: str, *, project_id: str | None) -> list[dict[str, Any]]:
    from psycopg.rows import dict_row

    from app.services.crash_store_postgres import _crash_db_url
    from app.services.postgres_schema import connect_postgres, ensure_app_postgres_schema

    pid = _postgres_project_id(project_id)
    with connect_postgres(_crash_db_url(), row_factory=dict_row) as conn:
        ensure_app_postgres_schema(conn)
        with conn.cursor() as cur:
            cur.execute(
                """
                SELECT id, crash_id, role, message, status, iteration, created_at
                FROM crash_feedback
                WHERE firebase_project_id = %s AND crash_id = %s
                ORDER BY id ASC
                """,
                (pid, crash_id),
            )
            rows = cur.fetchall()
    out: list[dict[str, Any]] = []
    for row in rows:
        d = dict(row)
        if d.get("created_at") is not None and not isinstance(d["created_at"], str):
            d["created_at"] = d["created_at"].isoformat()
        out.append(d)
    return out
