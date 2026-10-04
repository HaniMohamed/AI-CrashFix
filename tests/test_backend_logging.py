from __future__ import annotations

import logging
from pathlib import Path

from app.services.backend_logging import (
    backend_log_path,
    build_uvicorn_log_config,
    ensure_backend_file_logging,
)


def test_backend_log_path_uses_fixora_data_dir(monkeypatch, tmp_path: Path) -> None:
    data_dir = tmp_path / "Fixora"
    data_dir.mkdir()
    monkeypatch.setenv("AI_CRASH_FIX_DATA_DIR", str(data_dir))

    assert backend_log_path() == data_dir / "backend.log"


def test_ensure_backend_file_logging_writes_to_data_dir(
    monkeypatch, tmp_path: Path
) -> None:
    data_dir = tmp_path / "Fixora"
    data_dir.mkdir()
    monkeypatch.setenv("AI_CRASH_FIX_DATA_DIR", str(data_dir))

    path = ensure_backend_file_logging(log_level="info")
    assert path == data_dir / "backend.log"
    assert path.is_file()

    logging.getLogger("app.test").info("hello from test")
    for handler in logging.getLogger().handlers:
        if hasattr(handler, "flush"):
            handler.flush()

    text = path.read_text(encoding="utf-8")
    assert "Backend logging to" in text
    assert "hello from test" in text


def test_build_uvicorn_log_config_includes_file_handler(
    monkeypatch, tmp_path: Path
) -> None:
    data_dir = tmp_path / "Fixora"
    data_dir.mkdir()
    log_path = data_dir / "backend.log"
    monkeypatch.setenv("AI_CRASH_FIX_DATA_DIR", str(data_dir))

    config = build_uvicorn_log_config(log_path, "info")
    assert config["handlers"]["file"]["filename"] == str(log_path)
    assert "file" in config["loggers"]["uvicorn"]["handlers"]
