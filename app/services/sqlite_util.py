"""Shared SQLite connection helpers to avoid FD exhaustion under load."""

from __future__ import annotations

import sqlite3
import threading

_schema_lock = threading.Lock()
_schema_ready: set[str] = set()


def connect_sqlite(db_path: str, *, timeout: float = 60.0) -> sqlite3.Connection:
    """
    Open a SQLite connection with settings suited to concurrent readers/writers.

    Callers must close the connection (prefer ``with connect_sqlite(...) as conn:``).
    """
    conn = sqlite3.connect(str(db_path), timeout=float(timeout), check_same_thread=False)
    try:
        conn.execute("PRAGMA busy_timeout = 60000")
        conn.execute("PRAGMA journal_mode = WAL")
        conn.execute("PRAGMA synchronous = NORMAL")
        conn.execute("PRAGMA temp_store = MEMORY")
    except sqlite3.Error:
        # PRAGMA failures should not block basic connectivity.
        pass
    return conn


def schema_needs_ensure(db_path: str) -> bool:
    path = str(db_path)
    with _schema_lock:
        return path not in _schema_ready


def mark_schema_ensured(db_path: str) -> None:
    path = str(db_path)
    with _schema_lock:
        _schema_ready.add(path)


def reset_schema_cache_for_tests() -> None:
    with _schema_lock:
        _schema_ready.clear()
