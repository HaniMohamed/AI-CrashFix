"""File logging for the Fixora backend (``backend.log`` in the data directory)."""

from __future__ import annotations

import logging
import sys
from pathlib import Path

_CONFIGURED_PATH: Path | None = None

_LOG_FORMAT = "%(asctime)s %(levelname)s [%(name)s] %(message)s"
_LOG_DATEFMT = "%Y-%m-%d %H:%M:%S"


def backend_log_path() -> Path | None:
    from app.services.log_files import resolve_data_dir

    base = resolve_data_dir()
    if base is None:
        return None
    return base / "backend.log"


def _normalize_level(log_level: str) -> int:
    return getattr(logging, str(log_level or "info").upper(), logging.INFO)


def _has_file_handler_for(path: Path) -> bool:
    target = str(path.resolve())
    root = logging.getLogger()
    for handler in root.handlers:
        if isinstance(handler, logging.FileHandler):
            try:
                if Path(handler.baseFilename).resolve() == Path(target).resolve():
                    return True
            except OSError:
                continue
    for name in ("uvicorn", "uvicorn.error", "uvicorn.access"):
        for handler in logging.getLogger(name).handlers:
            if isinstance(handler, logging.FileHandler):
                try:
                    if Path(handler.baseFilename).resolve() == Path(target).resolve():
                        return True
                except OSError:
                    continue
    return False


def build_uvicorn_log_config(log_path: Path, log_level: str) -> dict[str, object]:
    level = str(log_level or "info").upper()
    return {
        "version": 1,
        "disable_existing_loggers": False,
        "formatters": {
            "default": {
                "format": _LOG_FORMAT,
                "datefmt": _LOG_DATEFMT,
            },
        },
        "handlers": {
            "file": {
                "class": "logging.FileHandler",
                "formatter": "default",
                "filename": str(log_path),
                "encoding": "utf-8",
                "mode": "a",
            },
            "default": {
                "class": "logging.StreamHandler",
                "formatter": "default",
                "stream": "ext://sys.stderr",
            },
        },
        "loggers": {
            "uvicorn": {
                "handlers": ["default", "file"],
                "level": level,
                "propagate": False,
            },
            "uvicorn.error": {
                "handlers": ["default", "file"],
                "level": level,
                "propagate": False,
            },
            "uvicorn.access": {
                "handlers": ["file"],
                "level": level,
                "propagate": False,
            },
        },
        "root": {"handlers": ["default", "file"], "level": level},
    }


def ensure_backend_file_logging(*, log_level: str = "info") -> Path | None:
    """
    Append backend logs to ``backend.log`` under the app data directory.

    Safe to call multiple times (e.g. uvicorn CLI + lifespan). Returns the log
    file path when configured, else ``None``.
    """
    global _CONFIGURED_PATH

    path = backend_log_path()
    if path is None:
        return None

    if _CONFIGURED_PATH == path and _has_file_handler_for(path):
        return path

    try:
        path.parent.mkdir(parents=True, exist_ok=True)
    except OSError:
        return None

    level = _normalize_level(log_level)
    formatter = logging.Formatter(_LOG_FORMAT, datefmt=_LOG_DATEFMT)

    file_handler = logging.FileHandler(path, encoding="utf-8", mode="a")
    file_handler.setFormatter(formatter)
    file_handler.setLevel(level)

    if not _has_file_handler_for(path):
        logging.getLogger().addHandler(file_handler)
        for name in ("uvicorn", "uvicorn.error", "uvicorn.access"):
            logging.getLogger(name).addHandler(file_handler)

    logging.getLogger().setLevel(min(level, logging.getLogger().level or level))
    _CONFIGURED_PATH = path

    logging.getLogger(__name__).info("Backend logging to %s", path)
    return path


def uvicorn_log_config(log_level: str = "info") -> dict[str, object] | None:
    """Build a uvicorn ``log_config`` dict, or ``None`` when no data dir exists."""
    path = backend_log_path()
    if path is None:
        return None
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
    except OSError:
        return None
    global _CONFIGURED_PATH
    _CONFIGURED_PATH = path
    return build_uvicorn_log_config(path, log_level)
