from __future__ import annotations

import os
import sys
from dataclasses import dataclass
from pathlib import Path

_LOG_NAMES = {
    "backend": "backend.log",
    "launcher": "launcher.log",
}


def resolve_data_dir() -> Path | None:
    """Writable app data directory (env or default macOS Application Support)."""
    raw = (os.environ.get("AI_CRASH_FIX_DATA_DIR") or "").strip()
    if raw:
        try:
            return Path(raw).expanduser().resolve()
        except Exception:
            return None
    if sys.platform == "darwin":
        from app.brand import resolve_macos_application_support

        return resolve_macos_application_support()
    return None


def resolve_log_path(source: str) -> Path | None:
    """Return an absolute log file path for ``backend`` or ``launcher``, or None."""
    name = _LOG_NAMES.get((source or "").strip().lower())
    if not name:
        return None
    base = resolve_data_dir()
    if base is None:
        return None
    try:
        base_resolved = base.resolve()
        path = (base_resolved / name).resolve()
        path.relative_to(base_resolved)
    except (ValueError, OSError):
        return None
    return path


@dataclass(frozen=True)
class LogReadResult:
    source: str
    path: str
    data_dir: str | None
    available: bool
    size: int
    offset: int
    next_offset: int
    content: str
    truncated: bool
    message: str | None = None


def read_log_chunk(
    source: str,
    *,
    offset: int = 0,
    max_bytes: int = 512_000,
    tail: bool = True,
) -> LogReadResult:
    """
    Read a slice of a launcher/backend log file.

    ``offset`` is a byte offset into the file. When ``offset`` is 0, the file
    is larger than ``max_bytes``, and ``tail`` is true, only the last
    ``max_bytes`` are returned with ``truncated=True``.
    """
    src = (source or "").strip().lower()
    path = resolve_log_path(src)
    base = path.parent if path is not None else resolve_data_dir()
    if path is None:
        return LogReadResult(
            source=src,
            path="",
            data_dir=str(base) if base else None,
            available=False,
            size=0,
            offset=0,
            next_offset=0,
            content="",
            truncated=False,
            message="Unknown log source or data directory is not configured.",
        )

    path_str = str(path)
    if not path.is_file():
        hint = (
            f"Log file not found at {path_str}. "
            "The Fixora backend writes backend.log under "
            "~/Library/Application Support/Fixora/ when started from the app."
        )
        return LogReadResult(
            source=src,
            path=path_str,
            data_dir=str(base) if base else None,
            available=False,
            size=0,
            offset=0,
            next_offset=0,
            content="",
            truncated=False,
            message=hint,
        )

    cap = max(1024, min(int(max_bytes), 1_048_576))
    size = path.stat().st_size
    start = max(0, int(offset))

    if start > size:
        start = max(0, size - cap)

    truncated = False
    if start == 0 and size > cap:
        if tail:
            start = size - cap
            truncated = True
        else:
            truncated = True

    end = min(size, start + cap)
    if end <= start:
        return LogReadResult(
            source=src,
            path=path_str,
            data_dir=str(base) if base else None,
            available=True,
            size=size,
            offset=start,
            next_offset=size,
            content="",
            truncated=truncated,
        )

    with path.open("rb") as fh:
        fh.seek(start)
        raw = fh.read(end - start)

    text = raw.decode("utf-8", errors="replace")
    if truncated and text and not text.startswith("\n"):
        text = "…\n" + text

    return LogReadResult(
        source=src,
        path=path_str,
        data_dir=str(base) if base else None,
        available=True,
        size=size,
        offset=start,
        next_offset=end,
        content=text,
        truncated=truncated,
    )
