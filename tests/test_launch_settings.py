from __future__ import annotations

import os
import tempfile
from pathlib import Path

from app.services.app_settings_store import AppSettingsStore
from app.services.launch_settings import persist_launch_env_overrides


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
            "AI_CRASH_FIX_CRASH_STORE_BACKEND,OPENAI_MODEL",
        )
        monkeypatch.setenv("AI_CRASH_FIX_CRASH_STORE_BACKEND", "postgres")
        monkeypatch.setenv("OPENAI_MODEL", "gpt-4o-mini")

        persisted = persist_launch_env_overrides()
        assert persisted == ["OPENAI_MODEL"]

        store = AppSettingsStore()
        assert store.get(k="OPENAI_MODEL") == "gpt-4o-mini"
        assert store.get(k="AI_CRASH_FIX_CRASH_STORE_BACKEND") is None
