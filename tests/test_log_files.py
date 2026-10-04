from __future__ import annotations

from pathlib import Path

from app.services.log_files import read_log_chunk, resolve_log_path


def test_resolve_log_path_uses_fixora_data_dir(monkeypatch, tmp_path: Path) -> None:
    home = tmp_path / "home"
    fixora = home / "Library" / "Application Support" / "Fixora"
    fixora.mkdir(parents=True)
    (fixora / "backend.log").write_text("fixora\n", encoding="utf-8")
    monkeypatch.setenv("HOME", str(home))
    monkeypatch.delenv("AI_CRASH_FIX_DATA_DIR", raising=False)

    path = resolve_log_path("backend")
    assert path == (fixora / "backend.log").resolve()


def test_resolve_log_path_ignores_legacy_folder(monkeypatch, tmp_path: Path) -> None:
    home = tmp_path / "home"
    fixora = home / "Library" / "Application Support" / "Fixora"
    legacy = home / "Library" / "Application Support" / "AI Crash Fix"
    fixora.mkdir(parents=True)
    legacy.mkdir(parents=True)
    (legacy / "backend.log").write_text("legacy\n", encoding="utf-8")
    monkeypatch.setenv("HOME", str(home))
    monkeypatch.delenv("AI_CRASH_FIX_DATA_DIR", raising=False)

    path = resolve_log_path("backend")
    assert path == (fixora / "backend.log").resolve()
    assert not path.is_file()


def test_read_log_chunk_reports_missing_fixora_log(monkeypatch, tmp_path: Path) -> None:
    home = tmp_path / "home"
    fixora = home / "Library" / "Application Support" / "Fixora"
    fixora.mkdir(parents=True)
    monkeypatch.setenv("HOME", str(home))
    monkeypatch.delenv("AI_CRASH_FIX_DATA_DIR", raising=False)

    result = read_log_chunk("backend")
    assert result.available is False
    assert result.path.endswith("Fixora/backend.log")
    assert "Fixora" in (result.message or "")


def test_resolve_log_path_honors_explicit_data_dir(
    monkeypatch, tmp_path: Path
) -> None:
    data_dir = tmp_path / "custom"
    data_dir.mkdir()
    (data_dir / "backend.log").write_text("custom\n", encoding="utf-8")
    monkeypatch.setenv("AI_CRASH_FIX_DATA_DIR", str(data_dir))

    path = resolve_log_path("backend")
    assert path == (data_dir / "backend.log").resolve()
