"""Shared SQLite connection helpers to avoid FD exhaustion under load."""

from __future__ import annotations

import sqlite3
import threading
from collections.abc import Iterator
from contextlib import contextmanager
from typing import Any


_schema_lock = threading.Lock()
_schema_ready: set[str] = set()


@contextmanager
def connect_sqlite(
    db_path: str,
    *,
    timeout: float = 60.0,
    row_factory: Any | None = None,
) -> Iterator[sqlite3.Connection]:
    """
    Open a SQLite connection and **always close it** on exit.

    Important: ``sqlite3.Connection``'s own context manager only commits/rollbacks;
    it does **not** close the connection. Always use this helper (or close manually).
    """
    conn = sqlite3.connect(str(db_path), timeout=float(timeout), check_same_thread=False)
    try:
        if row_factory is not None:
            conn.row_factory = row_factory
        try:
            conn.execute("PRAGMA busy_timeout = 60000")
            conn.execute("PRAGMA journal_mode = WAL")
            conn.execute("PRAGMA synchronous = NORMAL")
            conn.execute("PRAGMA temp_store = MEMORY")
        except sqlite3.Error:
            # PRAGMA failures should not block basic connectivity.
            pass
        yield conn
    finally:
        conn.close()


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
