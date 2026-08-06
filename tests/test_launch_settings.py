from __future__ import annotations

import os
import tempfile
from pathlib import Path

from app.services.app_settings_store import AppSettingsStore
from app.services.launch_settings import apply_launch_env_file, persist_launch_env_overrides


def test_persist_launch_env_overrides_writes_llm_keys(monkeypatch) -> None:
    with tempfile.TemporaryDirectory() as tmp:
        db = Path(tmp) / "repo_registry.db"
        monkeypatch.setenv("AI_CRASH_FIX_REPO_REGISTRY_DB", str(db))
        monkeypatch.setenv(
            "AI_CRASH_FIX_LAUNCH_ENV_KEYS",
            "LLM_PROVIDER,OPENAI_MODEL,OPENAI_URL",
        )
        monkeypatch.setenv("LLM_PROVIDER", "openai")
        monkeypatch.setenv("OPENAI_MODEL", "meta-llama/llama-3.3-70b-instruct")
        monkeypatch.setenv("OPENAI_URL", "https://openrouter.ai/api/v1")

        persisted = persist_launch_env_overrides()
        assert persisted == ["LLM_PROVIDER", "OPENAI_MODEL", "OPENAI_URL"]

        store = AppSettingsStore()
        assert store.get(k="LLM_PROVIDER") == "openai"
        assert store.get(k="OPENAI_MODEL") == "meta-llama/llama-3.3-70b-instruct"
        assert store.get(k="OPENAI_URL") == "https://openrouter.ai/api/v1"


def test_persist_launch_env_overrides_noop_without_marker(monkeypatch) -> None:
    with tempfile.TemporaryDirectory() as tmp:
        db = Path(tmp) / "repo_registry.db"
        monkeypatch.setenv("AI_CRASH_FIX_REPO_REGISTRY_DB", str(db))
        monkeypatch.delenv("AI_CRASH_FIX_LAUNCH_ENV_KEYS", raising=False)
        monkeypatch.setenv("LLM_PROVIDER", "openai")

        store = AppSettingsStore()
        store.set(k="OPENAI_MODEL", v="old-model")

        assert persist_launch_env_overrides() == []
        assert store.get(k="OPENAI_MODEL") == "old-model"


def test_persist_launch_env_overrides_skips_unknown_keys(monkeypatch) -> None:
    with tempfile.TemporaryDirectory() as tmp:
        db = Path(tmp) / "repo_registry.db"
        monkeypatch.setenv("AI_CRASH_FIX_REPO_REGISTRY_DB", str(db))
        monkeypatch.setenv(
            "AI_CRASH_FIX_LAUNCH_ENV_KEYS",
            "NOT_A_SETTINGS_KEY,OPENAI_MODEL",
        )
        monkeypatch.setenv("NOT_A_SETTINGS_KEY", "should-not-persist")
        monkeypatch.setenv("OPENAI_MODEL", "gpt-4o-mini")

        persisted = persist_launch_env_overrides()
        assert persisted == ["OPENAI_MODEL"]

        store = AppSettingsStore()
        assert store.get(k="OPENAI_MODEL") == "gpt-4o-mini"
        assert store.get(k="NOT_A_SETTINGS_KEY") is None


def test_apply_launch_env_file_loads_and_marks_keys(monkeypatch, tmp_path: Path) -> None:
    env_file = tmp_path / "gosi-launch.env"
    env_file.write_text(
        "\n".join(
            [
                "LLM_PROVIDER=gosi-brain",
                'GOSI_BRAIN_AUTHORIZATION="Bearer eyJhbGciOiJIUzI1NiJ9.e30.x"',
                "GOSI_BRAIN_USER_ID=CR241011",
                "# comment",
                "",
            ]
        ),
        encoding="utf-8",
    )
    monkeypatch.setenv("AI_CRASH_FIX_ENV_FILE", str(env_file))
    monkeypatch.delenv("AI_CRASH_FIX_LAUNCH_ENV_KEYS", raising=False)
    monkeypatch.delenv("LLM_PROVIDER", raising=False)
    monkeypatch.delenv("GOSI_BRAIN_AUTHORIZATION", raising=False)
    monkeypatch.delenv("GOSI_BRAIN_USER_ID", raising=False)

    applied = apply_launch_env_file()
    assert "LLM_PROVIDER" in applied
    assert "GOSI_BRAIN_AUTHORIZATION" in applied
    assert os.environ["LLM_PROVIDER"] == "gosi-brain"
    assert os.environ["GOSI_BRAIN_AUTHORIZATION"] == "Bearer eyJhbGciOiJIUzI1NiJ9.e30.x"
    assert os.environ["GOSI_BRAIN_USER_ID"] == "CR241011"
    marker = os.environ["AI_CRASH_FIX_LAUNCH_ENV_KEYS"]
    assert "GOSI_BRAIN_AUTHORIZATION" in marker.split(",")


def test_persist_launch_env_overrides_from_env_file(monkeypatch, tmp_path: Path) -> None:
    db = tmp_path / "repo_registry.db"
    env_file = tmp_path / "launch.env"
    env_file.write_text(
        "LLM_PROVIDER=gosi-brain\nGOSI_BRAIN_USER_ID=CR241011\n",
        encoding="utf-8",
    )
    monkeypatch.setenv("AI_CRASH_FIX_REPO_REGISTRY_DB", str(db))
    monkeypatch.setenv("AI_CRASH_FIX_ENV_FILE", str(env_file))
    monkeypatch.delenv("AI_CRASH_FIX_LAUNCH_ENV_KEYS", raising=False)

    # Lifespan applies the file once, then persists — persist must not re-load.
    assert "LLM_PROVIDER" in apply_launch_env_file()
    persisted = persist_launch_env_overrides()
    assert "LLM_PROVIDER" in persisted
    assert "GOSI_BRAIN_USER_ID" in persisted
    store = AppSettingsStore()
    assert store.get(k="LLM_PROVIDER") == "gosi-brain"
    assert store.get(k="GOSI_BRAIN_USER_ID") == "CR241011"


def test_apply_launch_env_skips_store_keys_when_bootstrap_sqlite(
    monkeypatch, tmp_path: Path
) -> None:
    monkeypatch.setenv("AI_CRASH_FIX_DATA_DIR", str(tmp_path))
    from app.services.store_bootstrap import save_store_bootstrap

    save_store_bootstrap(backend="sqlite", user_id="alice")

    env_file = tmp_path / "launch.env"
    env_file.write_text(
        "\n".join(
            [
                "LLM_PROVIDER=gosi-brain",
                "AI_CRASH_FIX_CRASH_STORE_BACKEND=postgres",
                "AI_CRASH_FIX_CRASH_DB_URL=postgresql://ai:x@127.0.0.1:1/db",
            ]
        ),
        encoding="utf-8",
    )
    monkeypatch.setenv("AI_CRASH_FIX_ENV_FILE", str(env_file))
    monkeypatch.setenv("AI_CRASH_FIX_CRASH_STORE_BACKEND", "sqlite")
    monkeypatch.delenv("AI_CRASH_FIX_CRASH_DB_URL", raising=False)
    monkeypatch.delenv("AI_CRASH_FIX_LAUNCH_ENV_KEYS", raising=False)

    applied = apply_launch_env_file()
    assert "LLM_PROVIDER" in applied
    assert "AI_CRASH_FIX_CRASH_STORE_BACKEND" not in applied
    assert "AI_CRASH_FIX_CRASH_DB_URL" not in applied
    assert os.environ["AI_CRASH_FIX_CRASH_STORE_BACKEND"] == "sqlite"
    assert "AI_CRASH_FIX_CRASH_DB_URL" not in os.environ
    marker = os.environ.get("AI_CRASH_FIX_LAUNCH_ENV_KEYS", "")
    assert "AI_CRASH_FIX_CRASH_STORE_BACKEND" not in marker.split(",")
