from __future__ import annotations

import json
import os
from pathlib import Path

import pytest


@pytest.fixture()
def data_dir(monkeypatch, tmp_path: Path):
    monkeypatch.setenv("AI_CRASH_FIX_DATA_DIR", str(tmp_path))
    monkeypatch.setenv("AI_CRASH_FIX_CRASH_STORE_BACKEND", "sqlite")
    monkeypatch.delenv("AI_CRASH_FIX_CRASH_DB_URL", raising=False)
    monkeypatch.delenv("AI_CRASH_FIX_USER_ID", raising=False)
    import app.config as cfg

    monkeypatch.setattr(cfg, "AI_CRASH_FIX_CRASH_STORE_BACKEND", "sqlite")
    monkeypatch.setattr(cfg, "AI_CRASH_FIX_CRASH_DB_URL", None)
    monkeypatch.setattr(cfg, "AI_CRASH_FIX_USER_ID", None)
    from app.services.app_settings_store import AppSettingsStore
    from app.services.repo_registry_store import RepoRegistryStore

    AppSettingsStore.clear_shared_for_tests()
    RepoRegistryStore.clear_shared_for_tests()
    yield tmp_path
    AppSettingsStore.clear_shared_for_tests()
    RepoRegistryStore.clear_shared_for_tests()


def test_compose_db_url_merges_credentials():
    from app.services.store_bootstrap import compose_db_url

    assert (
        compose_db_url(
            "postgresql://db.example:5432/ai_crash_fix",
            username="ai",
            password="s3cret",
        )
        == "postgresql://ai:s3cret@db.example:5432/ai_crash_fix"
    )


def test_compose_db_url_preserves_existing_password_when_username_only():
    from app.services.store_bootstrap import compose_db_url

    out = compose_db_url(
        "postgresql://old:pass@db.example:5432/ai_crash_fix",
        username="new",
        password=None,
    )
    assert out == "postgresql://new:pass@db.example:5432/ai_crash_fix"


def test_save_and_apply_sqlite_bootstrap(data_dir, monkeypatch):
    from app.services.store_bootstrap import (
        apply_store_bootstrap_to_environ,
        configure_store,
        is_store_setup_complete,
        load_store_bootstrap,
        store_bootstrap_path,
    )

    assert is_store_setup_complete() is False
    result = configure_store(backend="sqlite", user_id="alice", test_connection=False)
    assert result["ok"] is True
    assert is_store_setup_complete() is True
    path = store_bootstrap_path()
    assert path is not None and path.is_file()
    raw = json.loads(path.read_text(encoding="utf-8"))
    assert raw["backend"] == "sqlite"
    assert raw["user_id"] == "alice"

    monkeypatch.setenv("AI_CRASH_FIX_CRASH_STORE_BACKEND", "postgres")
    monkeypatch.setenv("AI_CRASH_FIX_CRASH_DB_URL", "postgresql://x@localhost/db")
    applied = apply_store_bootstrap_to_environ()
    assert applied is not None
    assert applied["backend"] == "sqlite"
    assert load_store_bootstrap()["backend"] == "sqlite"
    assert os.environ["AI_CRASH_FIX_CRASH_STORE_BACKEND"] == "sqlite"
    assert "AI_CRASH_FIX_CRASH_DB_URL" not in os.environ


def test_configure_postgres_requires_url_and_user(data_dir):
    from app.services.store_bootstrap import configure_store

    with pytest.raises(ValueError, match="db_url"):
        configure_store(backend="postgres", user_id="alice", test_connection=False)

    with pytest.raises(ValueError, match="user_id"):
        configure_store(
            backend="postgres",
            db_url="postgresql://localhost:5432/ai_crash_fix",
            test_connection=False,
        )


def test_current_store_config_masks_password(data_dir, monkeypatch):
    from app.services.store_bootstrap import (
        current_store_config_public,
        save_store_bootstrap,
        apply_store_bootstrap_to_environ,
    )

    save_store_bootstrap(
        backend="postgres",
        db_url="postgresql://ai:s3cret@db.example:5432/ai_crash_fix",
        user_id="alice",
    )
    apply_store_bootstrap_to_environ()
    # Force backend name without requiring a live Postgres.
    monkeypatch.setenv("AI_CRASH_FIX_CRASH_STORE_BACKEND", "sqlite")
    pub = current_store_config_public()
    assert pub["has_db_url"] is True
    assert pub["db_url_masked"] is not None
    assert "s3cret" not in pub["db_url_masked"]
    assert "***" in pub["db_url_masked"]
